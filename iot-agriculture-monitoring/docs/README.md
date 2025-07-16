# Sistema IoT para Agricultura de Precisão

## Visão Geral
Sistema de monitoramento IoT para agricultura de precisão com arquitetura híbrida, combinando processamento local via Docker e infraestrutura em nuvem na Oracle Cloud (OCI).

![Arquitetura do Sistema](architecture.png)

## Arquitetura

### Ambiente Local (Docker)
- **Coleta de Dados**
  - Node.js API para coleta de dados dos sensores
  - Redis Cache para armazenamento temporário
  - PostgreSQL para dados locais
  - Processador Python para análise de dados

### Oracle Cloud Infrastructure (OCI)
- **Virtual Cloud Network (VCN)**
  - Internet Gateway para acesso externo
  - NAT Gateway para serviços internos
  - Subnets públicas e privadas

- **Serviços**
  - Compute Instance: Dashboard Web App (React.js + Express.js)
  - Object Storage: Armazenamento de logs e backups
  - MySQL Database: Dados processados e relatórios
  - MongoDB Atlas: Dados não estruturados e métricas
  - OCI Vault: Gerenciamento de chaves e segredos
  - API Gateway: Rate limiting e load balancing
  - Load Balancer: Distribuição de carga e alta disponibilidade

## Tecnologias Utilizadas

### Linguagens
- Node.js para API e Dashboard
- Python para processamento de dados
- SQL para dados estruturados

### Bancos de Dados
- MySQL: Dados processados
- MongoDB: Dados não estruturados
- Redis: Cache local
- PostgreSQL: Armazenamento local

### Infraestrutura
- Docker para containerização
- OCI para cloud
- Terraform para IaC
- Nginx para proxy reverso

## Setup do Projeto

### Requisitos
- Docker e Docker Compose
- Node.js
- Python 3
- Terraform
- Conta OCI configurada

### Instalação Local
1. Clone o repositório
2. Configure as variáveis de ambiente
3. Execute `docker-compose up -d`

### Deploy na OCI
1. Configure as credenciais OCI
2. Execute o script de deploy:
   ```bash
   cd cloud-infrastructure/scripts
   ./deploy.sh
   ```

## Estrutura do Projeto
```
iot-agriculture-monitoring/
├── cloud-infrastructure/
│   ├── api-server/
│   ├── scripts/
│   └── terraform/
├── database/
│   ├── mongodb/
│   └── mysql/
├── local-services/
│   ├── api-gateway/
│   ├── dashboard/
│   ├── data-processor/
│   └── sensor-simulator/
└── docs/
```

## Monitoramento e Manutenção

### Health Checks
- Verificações automáticas de saúde dos serviços
- Rollback automático em caso de falhas
- Logs centralizados

### Backup
- Backup automático dos bancos de dados
- Armazenamento em Object Storage
- Retenção configurável

### Segurança
- OCI Vault para segredos
- VCN com subnets isoladas
- Rate limiting via API Gateway
- SSL/TLS para comunicações

## Recursos Implementados
- SQL Database (PostgreSQL + MySQL)
- NoSQL Database (Redis + MongoDB)
- Node.js + Python
- Compute Instance + Object Storage
- OCI Vault
- VCN
- Internet Gateway + NAT Gateway
- Load Balancer 