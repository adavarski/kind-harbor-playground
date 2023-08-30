# ⚓ KinD Harbor : Deploy Harbor locally using KIND

Harbor Architecture:

<img src="pictures/Harbor-Architecture.png?raw=true" width="800">

Installing KinD & Harbor on Kubernetes (KinD):

```bash
$ make cluster
$ make add-host
Adding "core.harbor.domain" to /etc/hosts
$ cat /etc/hosts|tail -n2
# harbor
172.18.0.100	core.harbor.domain
$ make install

$ kubectl get po |grep harb
harbor-core-7bdb5c6655-xgn74                1/1     Running   1 (11h ago)   11h
harbor-database-0                           1/1     Running   0             11h
harbor-jobservice-c6b95f6d8-jddwg           1/1     Running   3 (11h ago)   11h
harbor-notary-server-f4dbc86fd-pm5wm        1/1     Running   2 (11h ago)   11h
harbor-notary-signer-5cfc9dcbf4-pt7f4       1/1     Running   2 (11h ago)   11h
harbor-portal-6d694b876b-vcbwj              1/1     Running   0             11h
harbor-redis-0                              1/1     Running   0             11h
harbor-registry-64b7c69575-c55zf            2/2     Running   0             11h
harbor-trivy-0                              1/1     Running   0             11
```
Open Browser https://core.harbor.domain and create `python` project:

<img src="pictures/harbor-create-project.png?raw=true" width="1000">

Setup image vulnarability scanning for the project:

<img src="pictures/harbor-project-python-hello-configure-scan.png?raw=true" width="1000">

Download `python` project REGISTRY CERTIFICATE locally (ca.crt file):

<img src="pictures/harbor-project-python-registry-certificate-download.png?raw=true" width="1000">

Setup laptop docker daemon (docker host): 
```
$ cat /etc/docker/daemon.json
{
    "insecure-registries" : ["core.harbor.domain"]
}
$ sudo systemctl restart docker
```
Create docker image and push to Harbor docker registry:
```
$ cd python-docker-hello-kube
$ docker build . -t core.harbor.domain/python/hello:1.0
$ docker login core.harbor.domain (admin:Harbor12345)
$ docker push core.harbor.domain/python/hello:1.0
```
Setup KinD (ca.crt previously downloaded & /etc/hosts)
```
$ docker ps -a
CONTAINER ID   IMAGE                  COMMAND                  CREATED          STATUS          PORTS                       NAMES
c1a4414010b8   kindest/node:v1.26.0   "/usr/local/bin/entr…"   14 minutes ago   Up 14 minutes   127.0.0.1:44867->6443/tcp   harbor-control-plane

$ docker cp ca.crt harbor-control-plane:/usr/local/share/ca-certificates/
Successfully copied 3.07kB to harbor-control-plane:/usr/local/share/ca-certificates/

$ docker exec -it harbor-control-plane bash
root@harbor-control-plane:/# update-ca-certificates
Updating certificates in /etc/ssl/certs...
rehash: warning: skipping ca-certificates.crt,it does not contain exactly one certificate or CRL
1 added, 0 removed; done.
Running hooks in /etc/ca-certificates/update.d...
done.

root@harbor-control-plane:/# echo "172.18.0.100 core.harbor.domain" >> /etc/hosts
root@harbor-control-plane:/# systemctl restart containerd
```

Note: To Pull the image from the private registry, first, we need the create a secret containing the private registry credential. Create a secret object with docker-registry type.

```
$ kubectl create secret docker-registry harbor --docker-server=core.harbor.domain --docker-username=admin --docker-password=Harbor12345 --docker-email=root@testlab.local
secret/harbor created
```
Deploy python app:
```
$ cat deployment.yml 

apiVersion: v1
kind: Service
metadata:
  name: hello-service
spec:
  selector:
    app: hello
  ports:
  - protocol: "TCP"
    port: 5000
    targetPort: 5000
  type: LoadBalancer

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-deployment
spec:
  selector:
    matchLabels:
      app: hello
  replicas: 2
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
      - name: hello
        image: core.harbor.domain/python/hello:1.0
        imagePullPolicy: Always
        ports:
        - containerPort: 5000
      imagePullSecrets:
        - name: harbor

$ kubectl apply -f deployment.yml 
service/hello-service created
deployment.apps/hello-deployment created

$ kubectl get po|grep hello
hello-deployment-5d479bfff5-k6v5l           1/1     Running   0             12s
hello-deployment-5d479bfff5-lb7zp           1/1     Running   0             12s

$ kubectl get svc|grep hello
hello-service                        LoadBalancer   10.96.95.92     172.18.0.101   5000:30182/TCP               64s
$ curl 172.18.0.101:5000
Hello, Kube!
```
Clean env:
```
make cluster-delete
```

Ref: 
- https://github.com/jpb111/kubernetes-k0s-ansible-harbor
- https://ruzickap.github.io/k8s-harbor/part-06/#add-project
- https://goharbor.io/docs/1.10/working-with-projects/working-with-images/managing-helm-charts/
