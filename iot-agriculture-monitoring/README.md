# IoT Agriculture Monitoring System

Sistema de monitoramento IoT para agricultura, com coleta de dados de sensores, processamento e visualização em tempo real.

## Arquitetura

O sistema é composto por vários microserviços:

- **API Gateway**: Gerencia as requisições e roteamento
- **Dashboard**: Interface web para visualização dos dados
- **Data Processor**: Processamento dos dados dos sensores
- **Sensor Simulator**: Simulador de sensores IoT
- **Banco de dados**: MongoDB e MySQL
- **Cache**: Redis

## Pré-requisitos

- Docker e Docker Compose
- Node.js 18+
- Python 3.8+
- Terraform (para deploy na nuvem)

## Configuração Local

1. Clone o repositório:
```bash
git clone [URL_DO_REPOSITORIO]
cd iot-agriculture-monitoring
```

2. Crie os arquivos de ambiente necessários:
```bash
# Na raiz do projeto
cp .env.example .env

# No diretório dashboard
cp local-services/dashboard/config.example.js local-services/dashboard/config.js
```

3. Configure as variáveis de ambiente no arquivo `.env`

4. Inicie os serviços:
```bash
docker-compose up -d
```

5. Acesse o dashboard em `http://localhost:8088`

## Deploy na Nuvem (OCI)

1. Configure as credenciais da OCI no arquivo `terraform.tfvars`:
```hcl
tenancy_ocid     = "seu_tenancy_ocid"
user_ocid        = "seu_user_ocid"
fingerprint      = "sua_fingerprint"
private_key_path = "caminho_para_sua_chave_privada"
region           = "sua_regiao"
```

2. Inicialize e aplique o Terraform:
```bash
cd cloud-infrastructure/terraform
terraform init
terraform apply
```

3. Execute o script de deploy:
```bash
cd ../scripts
./deploy.sh
```

## Estrutura do Projeto

```
iot-agriculture-monitoring/
├── cloud-infrastructure/    # Configurações de infraestrutura
├── database/               # Scripts de inicialização dos bancos
├── docs/                   # Documentação
└── local-services/         # Microserviços
    ├── api-gateway/
    ├── dashboard/
    ├── data-processor/
    ├── nginx/
    └── sensor-simulator/
```

## Contribuindo

1. Faça um fork do projeto
2. Crie uma branch para sua feature (`git checkout -b feature/nova-feature`)
3. Commit suas mudanças (`git commit -am 'Adiciona nova feature'`)
4. Push para a branch (`git push origin feature/nova-feature`)
5. Crie um Pull Request

## Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes. 