#!/usr/bin/env bash

set -euo pipefail

CURDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add metallb https://metallb.github.io/metallb
helm repo add harbor https://helm.goharbor.io
helm repo update

# metallb
helm upgrade -i metallb metallb/metallb
kubectl wait --for=condition=ready pod --selector=app.kubernetes.io/name=metallb --timeout=90s
kubectl apply -f $CURDIR/config/lb-ipaddresspool.yaml 

# nginx
helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx -f $CURDIR/config/nginx.yaml 
kubectl wait --for=condition=ready pod --selector=app.kubernetes.io/name=ingress-nginx --timeout=90s
    
# harbor
helm upgrade -i harbor harbor/harbor -f $CURDIR/config/harbor.yaml 