FROM php:8.2-fpm-bookworm
LABEL maintainer="nikhilubale"

RUN apt-get update && apt-get install -y \
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev \
    libxml2-dev libxslt1-dev libzip-dev libicu-dev \
    libonig-dev libsodium-dev && \
    docker-php-ext-install \
    pdo_mysql bcmath soap xsl zip intl mbstring sodium sockets && \
    docker-php-ext-configure gd --with-freetype --with-jpeg && \
    docker-php-ext-install gd && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY www.conf /usr/local/etc/php-fpm.d/www.conf
RUN groupadd -g 1001 clp && useradd -u 1001 -g clp -m test-ssh
WORKDIR /var/www/html
EXPOSE 9000
