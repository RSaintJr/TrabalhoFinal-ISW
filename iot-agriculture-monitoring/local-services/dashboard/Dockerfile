# Usando NGINX para servir o dashboard
FROM nginx:alpine

# Copia os arquivos estáticos para o diretório padrão do NGINX
COPY . /usr/share/nginx/html

# Expõe a porta 80
EXPOSE 80

# Inicia o NGINX
CMD ["nginx", "-g", "daemon off;"]