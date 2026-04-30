# FocusBoard DevOps on Kubernetes

A full-stack task management application built with **Flask**, containerized with **Docker**, orchestrated with **Kubernetes**, and automated with **GitHub Actions CI/CD**.

This project started from a simple local Python web app and gradually became a real DevOps project with:

- Dockerfile
- Docker Compose
- PostgreSQL
- Redis
- Kubernetes Deployments and Services
- ConfigMap and Secret
- Persistent Volume Claim
- Health checks
- GitHub Actions CI
- Self-hosted runner for CD
- Automatic deployment to Kubernetes

---

## Project Goal

The goal of this repository is not only to run the application, but also to show a **step-by-step DevOps journey** from a local app to a fully automated CI/CD pipeline.

This README is written so that another learner can follow the same path, copy commands, and reproduce the project.

---

## Final Architecture

```text
User
  |
  v
FocusBoard Web App (Flask + Gunicorn)
  |
  +--> PostgreSQL (persistent data)
  |
  +--> Redis (cache)

GitHub Push
  |
  v
GitHub Actions (Build & Push Docker Image)
  |
  v
Docker Hub
  |
  v
Self-hosted Runner
  |
  v
Kubernetes Deploy
```

---

## Main Features of the App

- User registration and login
- Session-based authentication
- Add task
- Edit task
- Delete task
- Mark task as complete
- Filter by status
- Filter by category
- Filter by priority
- Search by title
- Predefined category dropdown with `Other`
- PostgreSQL for persistence
- Redis for caching filtered task results

---

## Repository Structure

```text
focusboard-devops-k8s/
│
├── .github/
│   └── workflows/
│       └── docker-image.yml
│
├── database/
│   └── schema.sql
│
├── k8s/
│   ├── cache-deployment.yaml
│   ├── cache-service.yaml
│   ├── db-deployment.yaml
│   ├── db-pv.yaml
│   ├── db-pvc.yaml
│   ├── db-service.yaml
│   ├── web-configmap.yaml
│   ├── web-deployment.yaml
│   ├── web-secret.yaml
│   └── web-service.yaml
│
├── static/
├── templates/
├── .dockerignore
├── .env.example
├── .gitignore
├── app.py
├── docker-compose.yml
├── Dockerfile
├── entrypoint.sh
├── init_db.py
├── requirements.txt
└── README.md
```

---

# Part 1 - Run the App Locally

## 1. Create a virtual environment

### Windows PowerShell

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
```

### Git Bash

```bash
python -m venv venv
source venv/Scripts/activate
```

---

## 2. Install dependencies

```bash
pip install -r requirements.txt
```

## 3. Run the app

```bash
python app.py
```

Open:

```text
http://localhost:5000
```

---

## 4. Swagger / FastAPI note

At the very beginning of the journey, an API-based version with FastAPI was tested. It worked, but it was not a real browser-friendly UI.  
That is why the project moved to a real **Flask web application with HTML templates**.

---

# Part 2 - Dockerize the App

## Why Docker?

Docker makes the app portable and reproducible.  
Instead of manually installing Python and dependencies every time, we package everything into an image.

---

## Final Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chmod +x /app/entrypoint.sh

EXPOSE 5000

ENTRYPOINT ["/app/entrypoint.sh"]
```

---

## Why not use `RUN python app.py` in Dockerfile?

Because:

- `RUN` executes during **image build**
- `CMD` or `ENTRYPOINT` executes during **container runtime**

If we used:

```dockerfile
RUN python app.py
```

the app would try to start while the image is still being built, which is not correct.

---

## Difference between RUN and ENTRYPOINT/CMD

### `RUN`
Used while building the image.

Example:

```dockerfile
RUN pip install -r requirements.txt
```

### `CMD` or `ENTRYPOINT`
Used when the container starts.

Example:

```dockerfile
ENTRYPOINT ["/app/entrypoint.sh"]
```

---

## Why `entrypoint.sh`?

The app depends on PostgreSQL.  
Before starting Gunicorn, we need to:

1. wait for PostgreSQL
2. initialize the database
3. start the app

That is why `entrypoint.sh` is used.

---

## Final `entrypoint.sh`

```bash
#!/bin/sh

echo "Waiting for PostgreSQL..."

until nc -z "$DB_HOST" "$DB_PORT"; do
  sleep 1
done

echo "Initializing database..."
python init_db.py

echo "Starting application..."
exec gunicorn --bind 0.0.0.0:5000 app:app
```

---

## What does `exec gunicorn --bind 0.0.0.0:5000 app:app` mean?

- `gunicorn` = production-grade WSGI server for Python web apps
- `--bind 0.0.0.0:5000` = listen on port 5000
- `app:app` = use the Flask app object named `app` inside `app.py`
- `exec` = replace the shell process with Gunicorn so signals are handled properly

This is the production-style equivalent of running the app, but better than plain:

```bash
python app.py
```

---

## Build Docker image manually

```bash
docker build -t focusboard .
```

---

## Run Docker container manually

```bash
docker run -p 5000:5000 focusboard
```

Open:

```text
http://localhost:5000
```

---

# Part 3 - Docker Compose

## Why Docker Compose?

Because the app is no longer just one container.

We need:

- web app
- PostgreSQL
- Redis

Compose lets us run all services together.

---

## Example `.env`

> Do not commit the real `.env` file to GitHub.

```env
SECRET_KEY=change-this-secret-key
DB_NAME=focusboard
DB_USER=focususer
DB_PASSWORD=focuspass
DB_HOST=db
DB_PORT=5432

REDIS_HOST=cache
REDIS_PORT=6379
```

---

## Final `docker-compose.yml`

```yaml
services:
  db:
    image: postgres:16
    container_name: focusboard-db
    restart: unless-stopped
    env_file:
      - .env
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  cache:
    image: redis:7
    container_name: focusboard-cache
    restart: unless-stopped
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  web:
    build: .
    container_name: focusboard-web
    restart: unless-stopped
    env_file:
      - .env
    depends_on:
      db:
        condition: service_healthy
      cache:
        condition: service_healthy
    ports:
      - "5000:5000"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 15s

volumes:
  postgres_data:
```

---

## Run with Docker Compose

```bash
docker compose up --build -d
```

Check containers:

```bash
docker compose ps
```

Open:

```text
http://localhost:5000
```

---

## Useful checks

### Initialize DB manually if needed

```bash
docker compose exec web python init_db.py
```

### Check Redis keys

```bash
docker compose exec cache redis-cli KEYS "tasks:user:*"
```

---

# Part 4 - Move to Kubernetes

## Why Kubernetes?

Docker Compose is good for local multi-container development.

Kubernetes is used for:

- orchestration
- scaling
- health management
- rolling updates
- production-style deployments

---

## Local Kubernetes cluster used in this project

This project used:

- **Docker Desktop Kubernetes**
- **kind-based cluster**
- 2 nodes

---

## Verify Kubernetes cluster

```bash
kubectl config current-context
kubectl get nodes
kubectl cluster-info
```

Expected context:

```text
docker-desktop
```

---

# Part 5 - Kubernetes Manifests

## 1. Web Deployment

The web app is deployed with:

- 2 replicas
- ConfigMap
- Secret
- health checks

### Final `k8s/web-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: focusboard-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: focusboard-web
  template:
    metadata:
      labels:
        app: focusboard-web
    spec:
      containers:
        - name: web
          image: nedakh126/focusboard-web:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 5000
          env:
            - name: DB_HOST
              valueFrom:
                configMapKeyRef:
                  name: focusboard-web-config
                  key: DB_HOST
            - name: DB_PORT
              valueFrom:
                configMapKeyRef:
                  name: focusboard-web-config
                  key: DB_PORT
            - name: DB_NAME
              valueFrom:
                configMapKeyRef:
                  name: focusboard-web-config
                  key: DB_NAME
            - name: REDIS_HOST
              valueFrom:
                configMapKeyRef:
                  name: focusboard-web-config
                  key: REDIS_HOST
            - name: REDIS_PORT
              valueFrom:
                configMapKeyRef:
                  name: focusboard-web-config
                  key: REDIS_PORT
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: focusboard-web-secret
                  key: DB_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: focusboard-web-secret
                  key: DB_PASSWORD
            - name: SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: focusboard-web-secret
                  key: SECRET_KEY
          readinessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 20
            periodSeconds: 15
            timeoutSeconds: 3
            failureThreshold: 3
```

---

## 2. Web Service

### `k8s/web-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: focusboard-web-service
spec:
  type: NodePort
  selector:
    app: focusboard-web
  ports:
    - port: 5000
      targetPort: 5000
      nodePort: 30007
```

---

## 3. PostgreSQL Deployment

### `k8s/db-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: focusboard-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: focusboard-db
  template:
    metadata:
      labels:
        app: focusboard-db
    spec:
      containers:
        - name: db
          image: postgres:16
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: "focusboard"
            - name: POSTGRES_USER
              value: "focususer"
            - name: POSTGRES_PASSWORD
              value: "focuspass"
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: focusboard-db-pvc
```

---

## 4. PostgreSQL Service

### `k8s/db-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db
spec:
  selector:
    app: focusboard-db
  ports:
    - port: 5432
      targetPort: 5432
```

---

## 5. Redis Deployment

### `k8s/cache-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: focusboard-cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: focusboard-cache
  template:
    metadata:
      labels:
        app: focusboard-cache
    spec:
      containers:
        - name: cache
          image: redis:7
          ports:
            - containerPort: 6379
```

---

## 6. Redis Service

### `k8s/cache-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cache
spec:
  selector:
    app: focusboard-cache
  ports:
    - port: 6379
      targetPort: 6379
```

---

# Part 6 - ConfigMap and Secret

## Why ConfigMap?

For non-sensitive values such as:

- DB host
- DB port
- DB name
- Redis host
- Redis port

### `k8s/web-configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: focusboard-web-config
data:
  DB_HOST: "db"
  DB_PORT: "5432"
  DB_NAME: "focusboard"
  REDIS_HOST: "cache"
  REDIS_PORT: "6379"
```

---

## Why Secret?

For sensitive values such as:

- DB user
- DB password
- Flask secret key

### `k8s/web-secret.yaml`

Using `stringData` is easier than manually encoding values in base64.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: focusboard-web-secret
type: Opaque
stringData:
  DB_USER: focususer
  DB_PASSWORD: focuspass
  SECRET_KEY: change-this-secret-key
```

---

# Part 7 - Persistent Volume and Persistent Volume Claim

## Important concept

### PV = PersistentVolume
The actual storage resource.

### PVC = PersistentVolumeClaim
The app's request for storage.

---

## Files used

### `k8s/db-pv.yaml`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: focusboard-db-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /tmp/postgres-data
```

### `k8s/db-pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: focusboard-db-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

---

## Note about local Kubernetes storage

In local Docker Desktop Kubernetes, storage behavior can differ from cloud environments.

- In cloud: PVC usually binds to a cloud storage class automatically.
- Locally: Kubernetes may create a dynamic volume using the default storage class.

Always verify with:

```bash
kubectl get pv
kubectl get pvc
```

Expected:

```text
STATUS: Bound
```

---

# Part 8 - Apply Kubernetes Resources

Apply files in order:

```bash
kubectl apply -f k8s/web-configmap.yaml
kubectl apply -f k8s/web-secret.yaml
kubectl apply -f k8s/db-pv.yaml
kubectl apply -f k8s/db-pvc.yaml
kubectl apply -f k8s/db-deployment.yaml
kubectl apply -f k8s/db-service.yaml
kubectl apply -f k8s/cache-deployment.yaml
kubectl apply -f k8s/cache-service.yaml
kubectl apply -f k8s/web-deployment.yaml
kubectl apply -f k8s/web-service.yaml
```

---

## Check resources

```bash
kubectl get deployments
kubectl get pods
kubectl get svc
kubectl get pv
kubectl get pvc
```

---

# Part 9 - Access the App

## Option 1 - NodePort
If your environment exposes NodePort correctly:

```text
http://localhost:30007
```

## Option 2 - Port Forward (recommended for local testing)

Run in background:

```bash
nohup kubectl port-forward service/focusboard-web-service 5000:5000 > portforward.log 2>&1 &
```

Then open:

```text
http://localhost:5000
```

# Part 10 - GitHub Actions CI

## Goal

Automate:

- Docker build
- Docker push to Docker Hub

---

## Docker Hub secrets used in GitHub

Create these repository secrets in GitHub:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

---

## Workflow file location

GitHub Actions workflows must be stored in:

```text
.github/workflows/
```

This is why the workflow file is **not** stored in `k8s/`.

---

## Initial CI workflow

The project first used a workflow that:

- built the image
- pushed `latest`
- pushed a SHA-based tag

---

# Part 11 - Self-hosted Runner for CD

## Why self-hosted runner?

Because the Kubernetes cluster is local on Docker Desktop.

A GitHub-hosted runner cannot directly access your local Kubernetes cluster.

So we use a **self-hosted runner** on the same Windows machine.

---

## Important note

If you use a self-hosted runner in a public repository, GitHub shows a warning because untrusted code could run on your machine.

For a personal learning project, this is acceptable, but for real production you must harden access and review pull requests carefully.

---

## Runner setup (Windows)

> Use **PowerShell** or **Windows Terminal**, not PowerShell ISE and not Git Bash for PowerShell-specific commands.

### Create runner directory

```powershell
mkdir C:\actions-runner
cd C:\actions-runner
```

### Download runner package

Get the latest command from GitHub, for example:

```powershell
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.334.0/actions-runner-win-x64-2.334.0.zip -OutFile actions-runner-win-x64-2.334.0.zip
```

### Extract runner

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD/actions-runner-win-x64-2.334.0.zip", "$PWD")
```

### Configure runner

Get the token from:

`GitHub Repo -> Settings -> Actions -> Runners -> New self-hosted runner`

Then run:

```powershell
.\config.cmd --url https://github.com/nedakhodabakhshi/focusboard-devops-k8s --token <YOUR_TOKEN>
```

When prompted, you can press Enter for defaults.

### Run runner

```powershell
.\run.cmd
```

Expected:

```text
Listening for Jobs
```

> Important: keep this terminal open.  
> If you close it, the runner stops.

---

# Part 12 - Full CI/CD Workflow

## Final workflow file

### `.github/workflows/docker-image.yml`

```yaml
name: Build, Push and Deploy Docker Image

on:
  push:
    branches:
      - main

env:
  IMAGE_NAME: nedakh126/focusboard-web

jobs:
  docker:
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.vars.outputs.image_tag }}

    steps:
      - name: Checkout source code
        uses: actions/checkout@v4

      - name: Set image tag
        id: vars
        run: echo "image_tag=sha-${GITHUB_SHA::7}" >> $GITHUB_OUTPUT

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:latest
            ${{ env.IMAGE_NAME }}:${{ steps.vars.outputs.image_tag }}

  deploy:
    needs: docker
    runs-on: self-hosted

    steps:
      - name: Deploy new image to Kubernetes
        shell: powershell
        run: |
          kubectl set image deployment/focusboard-web web=${{ env.IMAGE_NAME }}:${{ needs.docker.outputs.image_tag }}
          kubectl rollout status deployment/focusboard-web
```

---

## How it works

When you push to `main`:

1. GitHub Actions builds a new Docker image
2. Pushes it to Docker Hub
3. Self-hosted runner runs the deploy job
4. Kubernetes updates the deployment with the new image
5. Rollout completes automatically

---

# Part 13 - Verification Commands

## Check workflow result
Go to:

```text
GitHub Repo -> Actions
```

---

## Check Docker Hub tags

Verify the repository contains:

- `latest`
- `sha-<commit>`

---

## Check Kubernetes rollout

```bash
kubectl rollout status deployment/focusboard-web
```

---

## Check pods

```bash
kubectl get pods
```

---

## Check deployment image

```bash
kubectl describe deployment focusboard-web
```

# Part 14 - Final Result

At the end of this project, you have:

- a real Flask web application
- Dockerized environment
- multi-service setup with PostgreSQL and Redis
- Kubernetes manifests
- persistent storage
- ConfigMap and Secret usage
- health checks
- GitHub Actions CI
- self-hosted runner
- automated CD to local Kubernetes

This makes the project suitable for:

- DevOps portfolio
- interview discussion
- hands-on Kubernetes practice
- learning CI/CD end-to-end

---

## Author

Created as a hands-on DevOps learning project by **Neda Khodabakhshi**.

---



# Part 15 - Ingress (Production-style Access)

## Why Ingress?

NodePort and Port Forward are not ideal for real-world usage.

Ingress provides:

- clean URLs (no ports)
- domain-based routing
- production-like architecture

---

## Step 1 - Install NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

Wait until controller is ready:

```bash
kubectl get pods -n ingress-nginx
```

Expected:
Running

---

## Step 2 - Create Ingress Resource

Create a new file:

k8s/focusboard-ingress.yaml

### File content:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: focusboard-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: focusboard.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: focusboard-web-service
                port:
                  number: 5000
```

---

## Step 3 - Apply Ingress

```bash
kubectl apply -f k8s/focusboard-ingress.yaml
```

Check:

```bash
kubectl get ingress
```

---

## Step 4 - Configure local DNS (hosts file)

Edit:

C:\Windows\System32\drivers\etc\hosts

Add:

127.0.0.1 focusboard.local

---

## Step 5 - Access the App

Open in browser:

http://focusboard.local/login

---

## Final Result with Ingress

Browser → focusboard.local → Ingress → Service → Pods

---

## Important Notes

- Ingress Controller is installed once
- Ingress resource is applied once
- CI/CD only updates the Deployment image
- No need for port-forward anymore
- This setup is closer to real production environments

# Part 16 - Deploy with Helm (Professional Kubernetes Setup)

## Why Helm?

Managing many Kubernetes YAML files manually is hard and error-prone.

Helm helps us:

- reuse templates
- manage configuration in one place
- deploy with a single command
- upgrade easily without downtime

---

## Step 1 - Create Helm Chart

```bash
helm create focusboard-chart
```

---

## Step 2 - Helm Chart Structure

```text
focusboard-chart/
├── Chart.yaml
├── values.yaml
└── templates/
```

---

## Step 3 - values.yaml (Central Configuration)

```yaml
web:
  replicaCount: 2
  image:
    repository: nedakh126/focusboard-web
    tag: latest

db:
  image:
    repository: postgres
    tag: 16

cache:
  image:
    repository: redis
    tag: 7

config:
  DB_HOST: db
  DB_PORT: "5432"
  DB_NAME: focusboard
  REDIS_HOST: cache
  REDIS_PORT: "6379"

secret:
  DB_USER: focususer
  DB_PASSWORD: focuspass
  SECRET_KEY: change-this-secret-key
```

---

## Step 4 - Deploy with Helm

```bash
helm install focusboard ./focusboard-chart
```

---

## Step 5 - Upgrade

```bash
helm upgrade focusboard ./focusboard-chart
```

---

## Step 6 - Verify

```bash
kubectl get pods
kubectl get svc
kubectl get deployment
```

---

## Final Result

Helm replaces manual kubectl apply commands and provides a clean, reusable deployment method.

---

## Next Step

Deploy this Helm chart to AWS EKS with CI/CD (CodePipeline).
# Part 17 - AWS EKS Deployment with Terraform, ECR, Helm, EBS, and ALB

## Goal

In this stage, the FocusBoard project was moved from a local Kubernetes environment to a real AWS EKS cluster.

The goal was to build a clean, repeatable, cloud-based deployment process using:

* Terraform for AWS infrastructure
* ECR for storing the Docker image
* EKS for Kubernetes
* EBS CSI Driver for persistent PostgreSQL storage
* Helm for application deployment
* AWS Load Balancer Controller for ALB Ingress

---

## Final AWS Architecture

```text
User Browser
   |
   v
AWS Application Load Balancer (ALB)
   |
   v
Kubernetes Ingress
   |
   v
focusboard-web-service
   |
   v
FocusBoard Web Pods
   |
   +--> PostgreSQL Pod with EBS-backed PVC
   |
   +--> Redis Pod
```

---

# 17.1 - Terraform Folder Structure

For AWS, the Terraform code was split into two separate parts:

```text
terraform/
├── terraform-infra/
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── aws-load-balancer-controller-policy.json
│
└── terraform-k8s/
    ├── main.tf
    ├── provider.tf
    ├── variables.tf
    └── outputs.tf
```

## Why split Terraform into two folders?

At first, everything was in one Terraform folder.
But this caused problems because Kubernetes resources depend on the EKS cluster already existing.

So the project was split like this:

### `terraform-infra`

This folder creates AWS infrastructure:

* ECR repository
* IAM roles
* EKS cluster
* EKS node group
* EKS add-ons
* EBS CSI Driver
* IAM OIDC provider
* IAM role for AWS Load Balancer Controller

### `terraform-k8s`

This folder manages Kubernetes-side resources after the cluster exists:

* `aws-auth` ConfigMap
* StorageClass for EBS

This makes the project cleaner and easier to repeat.

---

# 17.2 - AWS Region and Account

The project was deployed in:

```text
Region: us-east-1
AWS Account ID: 557690612191
```

The default VPC was used:

```text
VPC ID: vpc-05b9fc4f0c956d7b8
```

---

# 17.3 - Create AWS Infrastructure with Terraform

Go to the infrastructure folder:

```bash
cd terraform/terraform-infra
```

Initialize Terraform:

```bash
terraform init
```

Format files:

```bash
terraform fmt
```

Validate configuration:

```bash
terraform validate
```

Check the execution plan:

```bash
terraform plan
```

Apply the infrastructure:

```bash
terraform apply
```

When prompted:

```text
yes
```

## What this created

Terraform created:

* ECR repository: `focusboard-web`
* EKS cluster: `focusboard-eks-cluster`
* EKS node group: `focusboard-node-group`
* 2 worker nodes
* IAM role for the EKS cluster
* IAM role for worker nodes
* EKS add-ons:

  * `vpc-cni`
  * `coredns`
  * `kube-proxy`
* EKS access entry for the IAM user

---

# 17.4 - Terraform Outputs

After apply, check outputs:

```bash
terraform output
```

Important outputs included:

```text
cluster_name
cluster_endpoint
ecr_repository_url
node_group_name
```

Example ECR output:

```text
557690612191.dkr.ecr.us-east-1.amazonaws.com/focusboard-web
```

---

# 17.5 - Connect kubectl to EKS

After the EKS cluster was created, kubectl was connected to the cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name focusboard-eks-cluster
```

Check the current context:

```bash
kubectl config current-context
```

Check worker nodes:

```bash
kubectl get nodes
```

Expected result:

```text
STATUS: Ready
```

---

# 17.6 - Kubernetes Access with Terraform

The project also configured Kubernetes access using Terraform.

The `terraform-k8s` folder was used for Kubernetes-related configuration.

Go to the folder:

```bash
cd ../terraform-k8s
```

Initialize Terraform:

```bash
terraform init
```

Apply Kubernetes configuration:

```bash
terraform apply
```

This managed the `aws-auth` ConfigMap and allowed the IAM user and node role to work properly with Kubernetes.

---

# 17.7 - EBS CSI Driver for Persistent Storage

PostgreSQL needs persistent storage so that data is not lost when the pod restarts.

For that, the AWS EBS CSI Driver was installed using Terraform in `terraform-infra`.

The infrastructure included:

* IAM OIDC provider
* IAM role for EBS CSI Driver
* AWS-managed policy:

  * `AmazonEBSCSIDriverPolicy`
* EKS add-on:

  * `aws-ebs-csi-driver`

After applying Terraform, the EBS CSI pods were checked:

```bash
kubectl get pods -n kube-system
```

Expected pods:

```text
ebs-csi-controller
ebs-csi-node
```

Expected status:

```text
Running
```

---

# 17.8 - Create EBS StorageClass with Terraform

A StorageClass was created in `terraform-k8s`.

StorageClass name:

```text
ebs-gp3
```

It uses:

```text
provisioner: ebs.csi.aws.com
type: gp3
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

Check it:

```bash
kubectl get storageclass
```

Expected:

```text
ebs-gp3
```

---

# 17.9 - Helm Structure for Local and AWS

The original Helm chart was kept for local Kubernetes.

A separate AWS Helm chart was created:

```text
helm/
├── focusboard-chart/
└── focusboard-chart-aws/
```

## Why create a separate AWS Helm chart?

The local chart was already working with Docker Desktop Kubernetes.

The AWS chart needed different settings:

* ECR image repository
* EBS StorageClass
* AWS ALB Ingress annotations
* AWS-specific deployment behavior

So instead of modifying the local Helm chart, a separate AWS chart was created:

```text
focusboard-chart      → local Kubernetes
focusboard-chart-aws  → AWS EKS
```

This keeps the project beginner-friendly and easy to follow step by step.

---

# 17.10 - Build Docker Image for AWS

Before deploying to EKS, the Docker image was built locally.

```bash
docker build --pull -t focusboard-web .
```

## Why `--pull`?

The Dockerfile starts with:

```dockerfile
FROM python:3.11-slim
```

That base image comes from Docker Hub.

The `--pull` option tells Docker to pull the latest version of the base image before building the FocusBoard image.

---

# 17.11 - Login to Amazon ECR

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 557690612191.dkr.ecr.us-east-1.amazonaws.com
```

This logs Docker into Amazon ECR.

---

# 17.12 - Tag and Push Image to ECR

Tag the image:

```bash
docker tag focusboard-web:latest 557690612191.dkr.ecr.us-east-1.amazonaws.com/focusboard-web:latest
```

Push it:

```bash
docker push 557690612191.dkr.ecr.us-east-1.amazonaws.com/focusboard-web:latest
```

Check ECR in AWS Console:

```text
ECR → Repositories → focusboard-web → Images
```

Expected image tag:

```text
latest
```

---

# 17.13 - AWS Helm Chart Changes

In the AWS Helm chart, the web image was changed to ECR:

```yaml
web:
  image:
    repository: 557690612191.dkr.ecr.us-east-1.amazonaws.com/focusboard-web
    tag: latest
    pullPolicy: Always
```

PostgreSQL persistence was configured to use EBS:

```yaml
db:
  persistence:
    enabled: true
    size: 5Gi
    accessMode: ReadWriteOnce
    storageClass: ebs-gp3
```

The PVC template used:

```yaml
storageClassName: {{ .Values.db.persistence.storageClass }}
```

---

# 17.14 - PostgreSQL EBS Fix

When PostgreSQL first started with EBS, it failed because the EBS volume contained a `lost+found` directory.

The fix was to add `PGDATA` in the PostgreSQL deployment:

```yaml
- name: PGDATA
  value: /var/lib/postgresql/data/pgdata
```

This makes PostgreSQL store data inside a subdirectory instead of directly at the root of the mounted EBS volume.

---

# 17.15 - Dockerfile Fix for AWS/Linux

The web pod initially failed with:

```text
exec /app/entrypoint.sh: no such file or directory
```

This was caused by Windows line endings in `entrypoint.sh`.

The Dockerfile was updated to clean Windows CRLF characters:

```dockerfile
RUN adduser --disabled-password --gecos "" appuser && \
    chown -R appuser:appuser /app && \
    sed -i 's/\r$//' /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh
```

Then the image was rebuilt and pushed again:

```bash
docker build --pull -t focusboard-web .
docker tag focusboard-web:latest 557690612191.dkr.ecr.us-east-1.amazonaws.com/focusboard-web:latest
docker push 557690612191.dkr.ecr.us-east-1.amazonaws.com/focusboard-web:latest
```

---

# 17.16 - Deploy FocusBoard to EKS with Helm

From the root of the project:

```bash
helm install focusboard ./helm/focusboard-chart-aws
```

If the release already exists:

```bash
helm upgrade focusboard ./helm/focusboard-chart-aws
```

Check resources:

```bash
kubectl get pods
kubectl get deployment
kubectl get svc
kubectl get pvc
kubectl get pv
```

Expected result:

```text
focusboard-cache   Running
focusboard-db      Running
focusboard-web     Running
PVC                Bound
```

---

# 17.17 - Verify NodePort Access

The web service was first exposed using NodePort:

```bash
kubectl get svc
```

Example:

```text
focusboard-web-service   NodePort   5000:30007/TCP
```

Get node public IPs:

```bash
kubectl get nodes -o wide
```

Open:

```text
http://<NODE_PUBLIC_IP>:30007/login
```

Example:

```text
http://54.91.19.188:30007/login
http://13.218.177.227:30007/login
```

Both node IPs worked because NodePort exposes the service through every worker node.

---

# 17.18 - AWS Load Balancer Controller

NodePort worked, but it is not production-friendly.

So AWS Load Balancer Controller was installed to create a real AWS Application Load Balancer from Kubernetes Ingress.

## Why AWS Load Balancer Controller?

In local Kubernetes, NGINX Ingress Controller was enough.

In AWS, we need a controller that can call AWS APIs and create:

* ALB
* Target Groups
* Listeners
* Security Group rules

That is why IAM permissions were required.

---

# 17.19 - IAM for AWS Load Balancer Controller

The IAM policy was downloaded:

```bash
curl -o aws-load-balancer-controller-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json
```

Terraform created:

* IAM policy for AWS Load Balancer Controller
* IAM role:

  * `focusboard-aws-load-balancer-controller-role`
* Policy attachment

Output:

```bash
terraform output aws_load_balancer_controller_role_arn
```

Example:

```text
arn:aws:iam::557690612191:role/focusboard-aws-load-balancer-controller-role
```

---

# 17.20 - Install AWS Load Balancer Controller with Helm

Add the AWS EKS Helm chart repo:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

Create service account:

```bash
kubectl create serviceaccount aws-load-balancer-controller -n kube-system
```

Annotate it with the IAM role:

```bash
kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::557690612191:role/focusboard-aws-load-balancer-controller-role
```

Install the controller:

```bash
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=focusboard-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

# 17.21 - Fix Load Balancer Controller VPC Detection

The controller initially failed because it could not detect the VPC ID from instance metadata.

It was fixed by upgrading the Helm release with explicit region and VPC ID:

```bash
helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=focusboard-eks-cluster \
  --set region=us-east-1 \
  --set vpcId=vpc-05b9fc4f0c956d7b8 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Check the controller:

```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

Expected:

```text
1/1 Running
1/1 Running
```

---

# 17.22 - Configure AWS ALB Ingress

The AWS Helm chart Ingress was configured with ALB annotations:

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: focusboard-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
    - http:
        paths:
          - path: {{ .Values.ingress.path }}
            pathType: {{ .Values.ingress.pathType }}
            backend:
              service:
                name: focusboard-web-service
                port:
                  number: {{ .Values.web.service.port }}
{{- end }}
```

Values:

```yaml
ingress:
  enabled: true
  className: alb
  host: ""
  path: /
  pathType: Prefix
```

---

# 17.23 - Apply ALB Ingress

Upgrade the FocusBoard Helm release:

```bash
helm upgrade focusboard ./helm/focusboard-chart-aws
```

Check Ingress:

```bash
kubectl get ingress
```

Expected:

```text
focusboard-ingress   alb   *   k8s-xxxx.us-east-1.elb.amazonaws.com   80
```

Describe Ingress:

```bash
kubectl describe ingress focusboard-ingress
```

Expected:

```text
SuccessfullyReconciled
```

---

# 17.24 - Access the App with ALB

Open the ALB DNS in the browser:

```text
http://<ALB-DNS>/login
```

Example:

```text
http://k8s-default-focusboa-b11cb04cea-1931201181.us-east-1.elb.amazonaws.com/login
```

---

# 17.25 - Useful Debug Commands

Check pods:

```bash
kubectl get pods
```

Check services:

```bash
kubectl get svc
```

Check PVC and PV:

```bash
kubectl get pvc
kubectl get pv
```

Check EBS CSI driver:

```bash
kubectl get pods -n kube-system | grep ebs
```

Check Load Balancer Controller:

```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

Check Ingress:

```bash
kubectl get ingress
kubectl describe ingress focusboard-ingress
```

Check app logs:

```bash
kubectl logs deployment/focusboard-web
```

Check database logs:

```bash
kubectl logs deployment/focusboard-db
```

---

# 17.26 - Cleanup to Avoid AWS Costs

When finished, delete application resources:

```bash
helm uninstall focusboard
```

Delete AWS Load Balancer Controller:

```bash
helm uninstall aws-load-balancer-controller -n kube-system
```

Destroy Kubernetes Terraform resources:

```bash
cd terraform/terraform-k8s
terraform destroy
```

Destroy AWS infrastructure:

```bash
cd ../terraform-infra
terraform destroy
```

When prompted:

```text
yes
```

---

# 17.27 - Final AWS Result

At the end of this AWS stage, the project had:

* Docker image stored in Amazon ECR
* EKS cluster created with Terraform
* 2 worker nodes
* PostgreSQL using EBS-backed PVC
* Redis running inside Kubernetes
* FocusBoard deployed with Helm
* NodePort access working
* AWS ALB Ingress working
* AWS Load Balancer Controller installed
* Terraform split into infrastructure and Kubernetes configuration

This completes the AWS deployment stage of the FocusBoard DevOps project.


