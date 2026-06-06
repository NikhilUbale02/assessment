FROM nginx:1.27-alpine
LABEL maintainer="nikhilubale"
RUN addgroup -g 1001 clp && adduser -u 1001 -G clp -D test-ssh
COPY conf.d/test.dyna.com.conf /etc/nginx/conf.d/default.conf
COPY certs/ /etc/nginx/certs/
COPY .htpasswd /etc/nginx/.htpasswd
EXPOSE 80 443
