FROM tarantool/tarantool:1.7
MAINTAINER andrey@tarantool.org

# install nginx
RUN addgroup -S nginx \
    && adduser -S -G nginx nginx \
    && apk add --no-cache 'su-exec>=0.2'

ENV NGINX_VERSION=1.11.1 \
    NGINX_UPSTREAM_MODULE_URL=https://github.com/tarantool/nginx_upstream_module.git \
    NGINX_UPSTREAM_MODULE_COMMIT=b4cbdca \
    NGINX_GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8

RUN set -x \
  && apk add --no-cache --virtual .build-deps \
     build-base \
     cmake \
     linux-headers \
     openssl-dev \
     pcre-dev \
     zlib-dev \
     libxslt-dev \
     gd-dev \
     geoip-dev \
     git \
     tar \
     gnupg \
     curl \
     perl-dev \
  && apk add --no-cache --virtual .run-deps \
     ca-certificates \
     openssl \
     pcre \
     zlib \
     libxslt \
     gd \
     geoip \
     perl \
     gettext \
  && : "---------- download nginx-upstream-module ----------" \
  && git clone "$NGINX_UPSTREAM_MODULE_URL" /usr/src/nginx_upstream_module \
  && git -C /usr/src/nginx_upstream_module submodule init \
  && git -C /usr/src/nginx_upstream_module submodule update \
  && make -C /usr/src/nginx_upstream_module yajl \
  && : "---------- download nginx ----------" \
  && curl -fSL http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz \
     -o nginx.tar.gz \
  && curl -fSL http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc \
     -o nginx.tar.gz.asc \
  && : "---------- verify signatures ----------" \
  && export GNUPGHOME="$(mktemp -d)" \
  && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$NGINX_GPG_KEYS" \
  && gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
  && rm -r "$GNUPGHOME" nginx.tar.gz.asc \
  && mkdir -p /usr/src/nginx \
  && tar -xzf nginx.tar.gz -C /usr/src/nginx \
      --strip-components=1 \
  && cd /usr/src/nginx \
  && : "---------- build nginx ----------" \
  && ./configure \
      --add-module=/usr/src/nginx_upstream_module \
      --prefix=/etc/nginx \
      --sbin-path=/usr/sbin/nginx \
      --modules-path=/usr/lib/nginx/modules \
      --conf-path=/etc/nginx/nginx.conf \
      --error-log-path=/var/log/nginx/error.log \
      --http-log-path=/var/log/nginx/access.log \
      --pid-path=/var/run/nginx.pid \
      --lock-path=/var/run/nginx.lock \
      --http-client-body-temp-path=/var/cache/nginx/client_temp \
      --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
      --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
      --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
      --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
      --user=nginx \
      --group=nginx \
      --with-http_ssl_module \
      --with-http_realip_module \
      --with-http_addition_module \
      --with-http_sub_module \
      --with-http_dav_module \
      --with-http_flv_module \
      --with-http_mp4_module \
      --with-http_gunzip_module \
      --with-http_gzip_static_module \
      --with-http_random_index_module \
      --with-http_secure_link_module \
      --with-http_stub_status_module \
      --with-http_auth_request_module \
      --with-http_xslt_module=dynamic \
      --with-http_image_filter_module=dynamic \
      --with-http_geoip_module=dynamic \
      --with-http_perl_module=dynamic \
      --with-threads \
      --with-stream \
      --with-stream_ssl_module \
      --with-http_slice_module \
      --with-mail \
      --with-mail_ssl_module \
      --with-file-aio \
      --with-http_v2_module \
      --with-ipv6 \
  && make \
  && make install \
  && rm -rf /etc/nginx/html/ \
  && mkdir /etc/nginx/conf.d/ \
  && mkdir -p /usr/share/nginx/html/ \
  && install -m644 html/index.html /usr/share/nginx/html/ \
  && install -m644 html/50x.html /usr/share/nginx/html/ \
  && : "---------- install module deps ----------" \
  && runDeps="$( \
      scanelf --needed --nobanner /usr/sbin/nginx /usr/lib/nginx/modules/*.so \
              | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
              | sort -u \
              | xargs -r apk info --installed \
              | sort -u \
      )" \
  && apk add --virtual .run-deps $runDeps \
  && : "---------- remove build deps ----------" \
  && rm -rf /usr/src/nginx \
  && rm -rf /usr/src/nginx_upstream_module \
  && apk del .build-deps \
  && : "---------- redirect logs to default collector ----------" \
  && ln -sf /dev/stdout /var/log/nginx/access.log \
  && ln -sf /dev/stderr /var/log/nginx/error.log

VOLUME ["/var/cache/nginx"]
EXPOSE 80 443

COPY dist/nginx.conf /etc/nginx/nginx.conf

# install supervisord
ENV PYTHON_VERSION=2.7.12-r0
ENV PY_PIP_VERSION=8.1.2-r0
ENV SUPERVISOR_VERSION=3.3.0
RUN apk update && apk add -u python=$PYTHON_VERSION py-pip=$PY_PIP_VERSION
RUN pip install supervisor==$SUPERVISOR_VERSION

# install tarantino
RUN mkdir /opt/tarantool/tarantino
COPY src/config.lua /opt/tarantool/tarantino
COPY src/const.lua /opt/tarantool/tarantino
COPY src/init.lua /opt/tarantool/tarantino
COPY src/parser.lua /opt/tarantool/tarantino
COPY src/request.lua /opt/tarantool/tarantino
COPY src/schema.lua /opt/tarantool/tarantino
COPY src/storage.lua /opt/tarantool/tarantino

COPY dist/docker.lua /opt/tarantool
COPY dist/service.json /opt/tarantool
COPY dist/supervisord.conf /etc/supervisord.conf

CMD ["supervisord"]
