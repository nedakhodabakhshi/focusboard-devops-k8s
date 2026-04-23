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

> Important:
>
> Use:
>
> ```bash
> pip install -r requirements.txt
> ```
---

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

---

# Part 10 - GitHub Repository Setup

## Suggested repository name

```text
focusboard-devops-k8s
```

## Suggested description

```text
FocusBoard is a full-stack task management application built with Flask, containerized using Docker, and deployed on Kubernetes. The project includes PostgreSQL for persistence, Redis for caching, and demonstrates real-world DevOps practices such as CI/CD pipelines, ConfigMaps, Secrets, health checks, and persistent volumes.
```

---

# Part 11 - GitHub Actions CI

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

# Part 12 - Self-hosted Runner for CD

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

# Part 13 - Full CI/CD Workflow

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

# Part 14 - Verification Commands

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

---

# Part 15 - Important Troubleshooting Notes

## 1. `pip install requirements.txt` error

Wrong:

```bash
pip install requirements.txt
```

Correct:

```bash
pip install -r requirements.txt
```

---

## 2. `TemplateNotFound: index.html`

Cause:
- wrong folder name
- missing `templates/index.html`

Fix:
- make sure HTML file is inside `templates/`

---

## 3. Login page not showing / direct access to home page

Cause:
- session still active
- route logic not enforcing login

Fix:
- enforce authentication checks before rendering index

---

## 4. `AssertionError: View function mapping is overwriting an existing endpoint function: login`

Cause:
- duplicate route definition for `/login`

Fix:
- keep only one login route in `app.py`

---

## 5. `.env` still pushed to GitHub even with `.gitignore`

Cause:
- `.env` was already tracked before `.gitignore`

Fix:

```bash
git rm --cached .env
git add .gitignore
git commit -m "Remove .env from repository tracking"
git push origin main
```

---

## 6. `Invoke-WebRequest: command not found`

Cause:
- PowerShell command executed in Git Bash

Fix:
- run it in **PowerShell**, not Git Bash

---

## 7. Runner stuck in PowerShell ISE

Cause:
- PowerShell ISE is not suitable for interactive runner setup

Fix:
- use normal PowerShell / Windows Terminal

---

## 8. Deploy job failed with `Unable to connect to the server`

Cause:
- Docker Desktop was not running
- local Kubernetes cluster was unavailable

Fix:
- open Docker Desktop
- confirm cluster access:

```powershell
kubectl config current-context
kubectl get nodes
kubectl cluster-info
```

---

## 9. Redis connection error in Kubernetes

Cause:
- Redis deployment/service not created yet

Fix:
- apply Redis manifests:

```bash
kubectl apply -f k8s/cache-deployment.yaml
kubectl apply -f k8s/cache-service.yaml
```

---

## 10. DB tables missing after DB recreation

Cause:
- PostgreSQL pod recreated, but web app not restarted to run `init_db.py`

Fix:

```bash
kubectl rollout restart deployment/focusboard-web
kubectl rollout status deployment/focusboard-web
```

---

# Part 16 - Security Notes

## Important

Do not commit real secret values to a public repository.

Use:

- `.env.example` for sample values
- GitHub Secrets for CI/CD
- Kubernetes Secret for deployment

If a real `.env` was ever pushed to a public repository, rotate:

- `SECRET_KEY`
- `DB_PASSWORD`
- any exposed tokens

---

# Part 17 - Useful Commands Reference

## Docker

```bash
docker build -t focusboard .
docker run -p 5000:5000 focusboard
docker compose up --build -d
docker compose ps
docker compose exec web python init_db.py
docker compose exec cache redis-cli KEYS "tasks:user:*"
```

## Kubernetes

```bash
kubectl get nodes
kubectl get pods
kubectl get svc
kubectl get deployments
kubectl get pv
kubectl get pvc
kubectl describe deployment focusboard-web
kubectl rollout status deployment/focusboard-web
kubectl rollout restart deployment/focusboard-web
kubectl port-forward service/focusboard-web-service 5000:5000
nohup kubectl port-forward service/focusboard-web-service 5000:5000 > portforward.log 2>&1 &
```

## Git / GitHub

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<your-username>/focusboard-devops-k8s.git
git push -u origin main
```

## Trigger CI/CD manually with an empty commit

```bash
git commit --allow-empty -m "Trigger pipeline"
git push origin main
```

---

# Part 18 - Final Result

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

## Suggested next improvements

- Ingress
- Helm chart
- EKS deployment
- monitoring with Prometheus and Grafana
- production-grade secret management
- GitHub Actions self-hosted runner as a Windows service
