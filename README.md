## ⚓ KinD Harbor : Deploy Harbor locally using KIND

### Harbor Architecture:

<img src="pictures/Harbor-Architecture.png?raw=true" width="800">

### Installing KinD & Harbor on Kubernetes (KinD):

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
### Open Browser https://core.harbor.domain and create `python` project:

<img src="pictures/harbor-create-project.png?raw=true" width="1000">

Setup image vulnarability scanning for the project:

<img src="pictures/harbor-project-python-hello-configure-scan.png?raw=true" width="1000">

Download `python` project REGISTRY CERTIFICATE locally (ca.crt file):

<img src="pictures/harbor-project-python-registry-certificate-download.png?raw=true" width="1000">

### Setup laptop docker daemon (docker host): 
```
$ cat /etc/docker/daemon.json
{
    "insecure-registries" : ["core.harbor.domain"]
}
$ sudo systemctl restart docker
```
### Create docker image and push to Harbor docker registry:
```
$ cd python-docker-hello-kube
$ docker build . -t core.harbor.domain/python/hello:1.0
$ docker login core.harbor.domain (admin:Harbor12345)
$ docker push core.harbor.domain/python/hello:1.0
```
### Setup KinD (ca.crt previously downloaded & /etc/hosts)
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

### Harbor Docker Private registry secret creation

Note: To Pull the image from the private registry, first, we need the create a secret containing the private registry credential. Create a secret object with docker-registry type.

```
$ kubectl create secret docker-registry harbor --docker-server=core.harbor.domain --docker-username=admin --docker-password=Harbor12345 --docker-email=root@testlab.local
secret/harbor created
```

### Deploy python app:
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

To delete deployment

$ kubectl delete deployment hello-deployment
```

### Creating a helm chart for the hello-kube application

In this section we will create a basic helm chart for the hello-kube python application and deploy it in the kubernetes cluster.

```
helm create hello-kube
```
This commnad will give the structure for the helm chart and create folder hello-kube. Since we are using a basic helm chart, We clean up the files and folderse in the hello-kube and make it in the below structure (helm-hello-kube folder in this repo)

Now we will edit the deployment.yaml file in the templates folder inside hello-kube
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-kube
spec:
  selector:
    matchLabels:
      app:  hello-kube
  replicas: {{ .Values.replicaCount }}
  template:
    metadata:
      labels:
        app:  hello-kube
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 5000
              protocol: TCP
```
ater we will edit the service.yaml file

```
apiVersion: v1
kind: Service
metadata:
  name: hello-kube
spec:
  selector:
    app: hello-kube
  ports:
  - protocol: "TCP"
    port: {{ .Values.service.port }}
    targetPort: http
  type: {{ .Values.service.type }}
```
Now we will edit the values.yaml file and add our configurations for deployment which will be passed as variable to deployment.yaml and service.yaml files.

```
# Default values for hello-kube.
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 1

image:
  repository: core.harbor.domain/python/hello
  pullPolicy: Always
  # Overrides the image tag whose default is the chart appVersion.
  tag: "1.0"

imagePullSecrets: 
  - name: harbor
service:
  type: LoadBalancer
  port: 5000
```
now install the helm chart
```
$ helm install hello-kube hello-kube
```
To delete the deployment

```
$ helm delete hello-kube
```

Package the application as a helm chart and upload it to a harbor helm chart registry.

```
helm package hello-kube
$ helm package hello-kube
Successfully packaged chart and saved it to: /tmp/kind-harbor-playground/hello-kube-0.1.0.tgz

```
### Push Helm Chart to OCI registry:

There are three options how helm charts can be pushed to Harbor

- 1.As you correctly found out yourself, you can install the helm addon chartmuseum/helm-push and use that to push Helm chart to Harbor
- 2.You create the Helm Chart locally with helm package and upload the tgz file via the Harbor UI
- 3.Since version 3.8 Helm support pushing and pulling Charts from OCI compliant container registries such as Harbor.

To be safe for the future, we recommend you switch to option 3, as Chartmuseum is already marked as deprecated in Harbor.

Here is a quick rundown how to push/pull Helm Chart to OCI compliant Registries
```
Before pulling or pushing Helm charts with the OCI-compatible registry of Harbor, Harbor should be logged with helm registry login command.

$ helm registry login -u admin --ca-file ./ca.crt https://core.harbor.domain
Password: 
Login Succeeded

$ helm push --ca-file ./ca.crt hello-kube-0.1.0.tgz oci://core.harbor.domain/python/hello
Pushed: core.harbor.domain/python/hello/hello-kube:0.1.0
Digest: sha256:e92385cc2daff9a0299630a29bb28a2710b1a796a5d1849b00ab62f1aa78400c
```
Pull and Install Helm Chart from OCI registry:

```
$ helm pull --ca-file ../ca.crt oci://core.harbor.domain/python/hello/hello-kube --version 0.1.0
Pulled: core.harbor.domain/python/hello/hello-kube:0.1.0
Digest: sha256:e92385cc2daff9a0299630a29bb28a2710b1a796a5d1849b00ab62f1aa78400c
$ ls
hello-kube-0.1.0.tgz
$ helm install hello-kube ./hello-kube-0.1.0.tgz 
NAME: hello-kube
LAST DEPLOYED: Wed Aug 30 07:51:38 2023
NAMESPACE: default
STATUS: deployed
REVISION: 1

$ kubectl get po|grep hell
hello-kube-5bff9b5f57-mq6zr                 1/1     Running   0             40s$ kubectl get svc|grep hello-kube
hello-kube                           LoadBalancer   10.96.82.244    172.18.0.102   5000:32373/TCP               93s
$ curl 172.18.0.102:5000

$ helm delete hello-kube
release "hello-kube" uninstalled

Note: This is pulling to tgz file to your current directory.
Unlike with the common approach where you would first add a repo and the pull from it in order to be able to install a Chart
you can do it all in one go with an OCI registry:

$ helm install hello-kube --ca-file ./ca.crt oci://core.harbor.domain/python/hello/hello-kube --version 0.1.0
Pulled: core.harbor.domain/python/hello/hello-kube:0.1.0
Digest: sha256:e92385cc2daff9a0299630a29bb28a2710b1a796a5d1849b00ab62f1aa78400c
NAME: hello-kube
LAST DEPLOYED: Wed Aug 30 07:56:43 2023
NAMESPACE: default
STATUS: deployed
REVISION: 1

$ kubectl get po|grep hello
hello-kube-5bff9b5f57-cq87w                 1/1     Running   0             30s
$ helm list
NAME         	NAMESPACE	REVISION	UPDATED                                 	STATUS  	CHART              	APP VERSION
harbor       	default  	1       	2023-08-29 19:55:02.419566648 +0300 EEST	deployed	harbor-1.12.4      	2.8.4      
hello-kube   	default  	1       	2023-08-30 07:56:43.829845076 +0300 EEST	deployed	hello-kube-0.1.0   	1.16.0     
ingress-nginx	default  	1       	2023-08-29 19:54:07.507984748 +0300 EEST	deployed	ingress-nginx-4.7.1	1.8.1      
metallb      	default  	1       	2023-08-29 19:53:05.309492749 +0300 EEST	deployed	metallb-0.13.10    	v0.13.10

Same procedure for template and upgrade

The oci:// protocol is also available in various other subcommands. Here is a complete list:

helm pull
helm show
helm template
helm install
helm upgrade

The Helm documentation has a https://helm.sh/docs/topics/registries/

```


### Clean env:
```
make cluster-delete
```

Ref: 
- https://github.com/jpb111/kubernetes-k0s-ansible-harbor
- https://ruzickap.github.io/k8s-harbor/part-06/#add-project
- https://goharbor.io/docs/1.10/working-with-projects/working-with-images/managing-helm-charts/
