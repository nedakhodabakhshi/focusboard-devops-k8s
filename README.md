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

# Part 18 - AWS CodePipeline CI/CD (Full Automation with EKS + Helm)

## Goal

In this final stage, the deployment process was fully automated using **AWS CodePipeline** and **AWS CodeBuild**.

The goal was:

- Automatically build Docker image
- Push image to Amazon ECR
- Deploy to EKS using Helm
- Trigger everything from GitHub push

---

## Final CI/CD Architecture

```text
GitHub Push
   |
   v
AWS CodePipeline
   |
   v
AWS CodeBuild
   |
   +--> Build Docker Image
   +--> Push to Amazon ECR
   +--> Deploy to EKS using Helm
   |
   v
Kubernetes (EKS Cluster)
   |
   v
Updated Pods (Rolling Update)
```

---

## 18.1 - GitHub Connection (CodeStar Connection)

To connect AWS with GitHub, a **CodeStar Connection** was created.

### Steps:

1. Go to AWS Console:

   ```text
   Developer Tools → Settings → Connections
   ```

2. Click:

   ```text
   Create connection
   ```

3. Choose:

   ```text
   GitHub (via GitHub App)
   ```

4. Authenticate and select repository:

   ```text
   nedakhodabakhshi/focusboard-devops-k8s
   ```

5. After creation, AWS generated a connection ARN like:

```text
arn:aws:codeconnections:us-east-1:557690612191:connection/xxxxxxxx
```

---

## 18.2 - IAM Role for CodePipeline

A custom IAM role was created using Terraform with permissions for:

- CodeBuild
- S3
- CodeStar Connections / CodeConnections

### Important permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "codebuild:StartBuild",
    "codebuild:BatchGetBuilds"
  ],
  "Resource": "*"
},
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
},
{
  "Effect": "Allow",
  "Action": [
    "codestar-connections:UseConnection",
    "codeconnections:UseConnection"
  ],
  "Resource": "<YOUR_CONNECTION_ARN>"
}
```

### Terraform example:

```hcl
resource "aws_iam_role" "codepipeline_role" {
  name = "focusboard-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "focusboard-codepipeline-role"
    Project = "focusboard"
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "focusboard-codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codeconnections:UseConnection",
          "codestar-connections:UseConnection"
        ]
        Resource = "<YOUR_CONNECTION_ARN>"
      }
    ]
  })
}
```

---

## 18.3 - IAM Role for CodeBuild

A custom IAM role was created for CodeBuild.

CodeBuild needed permissions for:

- Pulling source artifacts from the CodePipeline S3 bucket
- Logging to CloudWatch
- Logging in to ECR
- Pushing Docker images to ECR
- Describing the EKS cluster
- Deploying to EKS through Kubernetes access entries

### Important CodeBuild permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
    "ecr:PutImage",
    "ecr:BatchGetImage",
    "ecr:DescribeRepositories"
  ],
  "Resource": "*"
},
{
  "Effect": "Allow",
  "Action": [
    "eks:DescribeCluster"
  ],
  "Resource": "*"
},
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": "*"
},
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:GetObjectVersion",
    "s3:PutObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "<PIPELINE_BUCKET_ARN>",
    "<PIPELINE_BUCKET_ARN>/*"
  ]
}
```

### Why S3 access was needed

CodePipeline stores source artifacts in an S3 bucket before passing them to CodeBuild.

Without S3 permissions, CodeBuild failed with:

```text
AccessDenied: User is not authorized to perform: s3:GetObject
```

The fix was to add S3 permissions to the **CodeBuild role**.

---

## 18.4 - EKS Access Entry for CodeBuild

CodeBuild also needed permission to access Kubernetes inside EKS.

Terraform was used to create an EKS access entry for the CodeBuild role.

### Terraform example:

```hcl
resource "aws_eks_access_entry" "codebuild_access" {
  cluster_name  = aws_eks_cluster.focusboard_cluster.name
  principal_arn = aws_iam_role.codebuild_role.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "codebuild_admin" {
  cluster_name  = aws_eks_cluster.focusboard_cluster.name
  principal_arn = aws_iam_role.codebuild_role.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
```

### Why this was required

The buildspec uses:

```bash
aws eks update-kubeconfig
helm upgrade --install ...
```

So CodeBuild must be recognized by EKS as an authorized principal.

---

## 18.5 - CodeBuild Project

A CodeBuild project was created and connected to the pipeline.

### Responsibilities of CodeBuild:

- Build Docker image
- Tag image
- Push image to ECR
- Deploy to EKS using Helm

### Important setting

CodeBuild must use:

```text
Privileged mode: enabled
```

This is required because Docker builds run inside CodeBuild.

### Terraform example:

```hcl
resource "aws_codebuild_project" "focusboard_build" {
  name          = "focusboard-build"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/focusboard"
      stream_name = "build-log"
    }
  }

  tags = {
    Name    = "focusboard-codebuild"
    Project = "focusboard"
  }
}
```

---

## 18.6 - CodePipeline Project

The CodePipeline was created with two stages:

1. Source
2. Build

### Terraform example:

```hcl
resource "aws_codepipeline" "focusboard_pipeline" {
  name     = "focusboard-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = "<YOUR_CONNECTION_ARN>"
        FullRepositoryId = "nedakhodabakhshi/focusboard-devops-k8s"
        BranchName       = "aws-eks-codepipeline"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.focusboard_build.name
      }
    }
  }
}
```

---

## 18.7 - buildspec.yml (Critical File)

This file controls the entire CI/CD process.

### Final structure:

```yaml
version: 0.2

env:
  variables:
    AWS_DEFAULT_REGION: us-east-1
    AWS_ACCOUNT_ID: "557690612191"
    ECR_REPOSITORY_NAME: focusboard-web
    EKS_CLUSTER_NAME: focusboard-eks-cluster
    HELM_RELEASE_NAME: focusboard
    HELM_CHART_PATH: helm/focusboard-chart-aws

phases:
  install:
    commands:
      - echo "Installing kubectl..."
      - curl -LO "https://dl.k8s.io/release/v1.35.3/bin/linux/amd64/kubectl"
      - chmod +x kubectl
      - mv kubectl /usr/local/bin/kubectl

      - echo "Installing Helm..."
      - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

      - echo "Checking tool versions..."
      - aws --version
      - docker --version
      - kubectl version --client
      - helm version

  pre_build:
    commands:
      - echo "Logging in to Amazon ECR..."
      - ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$ECR_REPOSITORY_NAME"
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"

      - echo "Creating image tags..."
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=${COMMIT_HASH:=latest}
      - echo "Image tag is $IMAGE_TAG"

      - echo "Connecting kubectl to EKS..."
      - aws eks update-kubeconfig --region $AWS_DEFAULT_REGION --name $EKS_CLUSTER_NAME

  build:
    commands:
      - echo "Building Docker image..."
      - docker build --pull -t $ECR_REPOSITORY_NAME:latest .

      - echo "Tagging Docker image..."
      - docker tag $ECR_REPOSITORY_NAME:latest $ECR_URI:latest
      - docker tag $ECR_REPOSITORY_NAME:latest $ECR_URI:$IMAGE_TAG

  post_build:
    commands:
      - echo "Pushing Docker image to ECR..."
      - docker push $ECR_URI:latest
      - docker push $ECR_URI:$IMAGE_TAG

      - echo "Deploying to EKS using Helm..."
      - helm upgrade --install $HELM_RELEASE_NAME $HELM_CHART_PATH --set web.image.repository=$ECR_URI --set web.image.tag=$IMAGE_TAG

      - echo "Checking rollout status..."
      - kubectl rollout status deployment/focusboard-web

      - echo "Deployment completed successfully."

artifacts:
  files:
    - buildspec.yml
```

---

## 18.8 - CI/CD Steps inside CodeBuild

### 1. Install tools

CodeBuild installs:

- kubectl
- Helm

### 2. Authenticate to ECR

```bash
aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
```

### 3. Build Docker image

```bash
docker build --pull -t $ECR_REPOSITORY_NAME:latest .
```

### 4. Tag image

```bash
docker tag $ECR_REPOSITORY_NAME:latest $ECR_URI:latest
docker tag $ECR_REPOSITORY_NAME:latest $ECR_URI:$IMAGE_TAG
```

### 5. Push to ECR

```bash
docker push $ECR_URI:latest
docker push $ECR_URI:$IMAGE_TAG
```

### 6. Connect to EKS

```bash
aws eks update-kubeconfig --region $AWS_DEFAULT_REGION --name $EKS_CLUSTER_NAME
```

### 7. Deploy with Helm

```bash
helm upgrade --install $HELM_RELEASE_NAME $HELM_CHART_PATH --set web.image.repository=$ECR_URI --set web.image.tag=$IMAGE_TAG
```

---

## 18.9 - Important Debug Fixes

### Fix 1 - Do not store GitHub token in Terraform

At first, the pipeline used:

```hcl
OAuthToken = "ghp_xxxxx"
```

This is not secure and GitHub blocked the push because it detected a secret.

The solution was to use:

```text
CodeStarSourceConnection
```

instead of GitHub OAuth token.

---

### Fix 2 - CodePipeline needed permission to use GitHub Connection

The Source stage failed with:

```text
Unable to use Connection
```

The fix was to add this permission to the CodePipeline role:

```json
{
  "Effect": "Allow",
  "Action": [
    "codestar-connections:UseConnection",
    "codeconnections:UseConnection"
  ],
  "Resource": "<YOUR_CONNECTION_ARN>"
}
```

---

### Fix 3 - CodeBuild needed S3 permissions

CodeBuild failed with:

```text
AccessDenied: s3:GetObject
```

The fix was to add S3 permissions to the CodeBuild role.

---

### Fix 4 - Helm command must be one line

The pipeline failed with:

```text
helm upgrade requires 2 arguments
```

The fix was to make the Helm command one line in `buildspec.yml`:

```bash
helm upgrade --install $HELM_RELEASE_NAME $HELM_CHART_PATH --set web.image.repository=$ECR_URI --set web.image.tag=$IMAGE_TAG
```

---

## 18.10 - Push Changes to GitHub

After changing Terraform or buildspec files:

```bash
git status
git add .
git commit -m "Add AWS CodePipeline deployment"
git push origin aws-eks-codepipeline
```

The pipeline reads from:

```text
aws-eks-codepipeline
```

---

## 18.11 - Run the Pipeline

Go to:

```text
AWS Console → CodePipeline → focusboard-pipeline
```

Then click:

```text
Release change
```

Expected:

- Source → Succeeded
- Build → Succeeded

---

## 18.12 - Verify Deployment in Kubernetes

Connect kubectl to EKS:

```bash
aws eks update-kubeconfig --region us-east-1 --name focusboard-eks-cluster
```

Check pods:

```bash
kubectl get pods
```

Check deployments:

```bash
kubectl get deployment
```

Check services:

```bash
kubectl get svc
```

Check image version:

```bash
kubectl describe deployment focusboard-web | grep Image
```

Expected:

```text
557690612191.dkr.ecr.us-east-1.amazonaws.com/focusboard-web:<commit-tag>
```

---

## 18.13 - Verify Application via ALB

Check Ingress:

```bash
kubectl get ingress
```

If the ALB address exists, open:

```text
http://<ALB-DNS>/login
```

---

## 18.14 - Initialize Database if Needed

During testing, the application returned an internal error because the `users` table did not exist.

The fix was to run the database initialization script manually inside the web deployment:

```bash
kubectl exec deployment/focusboard-web -- python /app/init_db.py
```

Then restart the web deployment:

```bash
kubectl rollout restart deployment/focusboard-web
```

Check pods:

```bash
kubectl get pods
```

After this, registration and login worked successfully.

---

## 18.15 - Final Result of CodePipeline Stage

At the end of this stage, the project achieved:

- Full CI/CD with AWS CodePipeline
- GitHub integration via CodeStar Connection
- Automated Docker build and push to ECR
- Automated Helm deployment to EKS
- CodeBuild access to EKS using Access Entries
- Successful app deployment through the pipeline
- Application accessible through ALB

---

## 18.16 - Cleanup to Avoid AWS Costs

Delete application release:

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

Check these AWS services manually after cleanup:

```text
EC2 → Load Balancers
EC2 → Target Groups
EC2 → Volumes
EKS → Clusters
ECR → Repositories
S3 → Buckets
CodePipeline
CodeBuild
IAM Roles
```

---

## Final DevOps Achievement

This project now includes:

- Local development with Flask and Docker
- Docker Compose with PostgreSQL and Redis
- Kubernetes deployment with manifests
- Helm deployment
- GitHub Actions for local Kubernetes CI/CD
- AWS EKS deployment with Terraform
- EBS-backed PostgreSQL persistence
- AWS ALB Ingress
- Full AWS CodePipeline automation


