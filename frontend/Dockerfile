#---------Build Stage---------------
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package*.json ./

RUN npm ci && npm cache clean --force

COPY . .

RUN npm run build

#-------Prod Stage----------------
FROM nginx:1.30.3-alpine AS production

WORKDIR /app

RUN rm -rf /etc/nginx/conf.d/default.conf /usr/share/nginx/html/*

COPY --from=build /app/dist /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]

