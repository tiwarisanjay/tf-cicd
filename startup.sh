# use a local cluster like minikube to bootstrap a target cluster
# the end state might be local cluster only
ns=argocd
kubectl apply -n ${ns} -k https://github.com/bradfordwagner/deploy-argocd.git

echo awaiting argocd server + redis to startup
kubectl wait -n ${ns} deploy/argocd-server --for condition=available --timeout=5m
kubectl wait -n ${ns} deploy/argocd-redis  --for condition=available --timeout=5m

echo port forwarding argocd server
port_forward=8080
kubectl port-forward -n ${ns} deploy/argocd-server ${port_forward}:8080 &
sleep 3

# setup new password for argocd
argo_host=localhost:${port_forward}
initial_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "https://${argo_host}" | pbcopy
argocd login ${argo_host} \
  --username admin \
  --password ${initial_password} \
  --insecure
argocd account update-password \
  --account admin \
  --current-password ${initial_password} \
  --new-password admin1234
echo https://${argo_host} | pbcopy
echo https://${argo_host}

# add the downstream cluster to argocd
argocd cluster add --kubeconfig ~/.kube/personal infra-admin -y

# bootstrap all of our apps
kubectl apply -f argocd/bootstrap/app.yaml

