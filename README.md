# Try Me 

## What is this?

This is a simple project that runs three small programs on Kubernetes.

## What you need

Before you start, install these programs on your computer:

1. **Docker Desktop** - [Download here](https://www.docker.com/products/docker-desktop) 
2. **Minikube** - [Download here](https://minikube.sigs.k8s.io/docs/start/)
3. **kubectl** - [Download here](https://kubernetes.io/docs/tasks/tools/)
4. **Helm** - [Download here](https://helm.sh/docs/intro/install/)
5. **mkcert** - [Download here](https://github.com/FiloSottile/mkcert)



## How to use

### Step 1: Start Minikube

```bash
minikube start
```

### Step 2: Install everything

```bash
make deploy
```

This command will:
- Install monitoring tools (Prometheus and Grafana)
- Install the gateway
- Start all three services

Wait 3-5 minutes for everything to finish.

### Step 3: Start the services

```bash
make start-all
```

### Step 4: Open Grafana

Open your web browser and go to: **http://localhost:3000**

- Username: `admin`
- Password: `admin`

You will see dashboards showing how your services are working.

## What can you do?

### See all commands

```bash
make help
```

### Test if services are working

```bash
curl -k https://main-api.internal:8443/
curl -k https://main-api.internal:8443/auth
curl -k https://main-api.internal:8443/storage
```

### Test failure scenarios

```bash
make chaos-menu
```

This shows you different ways to test how the system handles problems.

### Stop everything

```bash
make stop-all
minikube stop
```

## The three services

1. **main-api** - The main service that handles requests
2. **auth-service** - Handles login and user checks  
3. **storage-service** - Handles file storage

## Monitoring

The project includes:
- **Grafana** - Shows graphs and charts about your services
- **Prometheus** - Collects information about your services
- **Alerts** - Sends notifications to Slack when something is wrong

## Alerts

You get alerts for:
- Service is down (no running pods)
- High latency (slow responses)
- High CPU usage (> 80%)
- High memory usage (> 85%)
- Login failures (too many failed logins)
- Upload failures (too many failed uploads)

## help

Run `make help` to see all available commands.

