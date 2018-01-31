wget https://nginx.org/keys/nginx_signing.key && apt-key add nginx_signing.key
apt-get update && apt-get dist-upgrade

cd /tmp && cd /tmp && apt-get source nginx && apt-get build-dep nginx

mkdir ./nginx-modules

wget -O ./ngx_http_redis.tar.gz https://people.freebsd.org/~osa/ngx_http_redis-0.3.8.tar.gz
tar vfx ./ngx_http_redis.tar.gz -C ./nginx-modules/


a=`ls ./nginx-1.*/debian/rules` && \
cp $a "$a.bak" && \
am=`n=0;ls -1 ./nginx-modules/ | while read m; do if [ $n -ge 1 ]; then echo -n " \\\\\\\\\n"; fi; echo -n "\1--add-module=\/tmp\/nginx-modules\/$m"; n=1; done;` && \
grep -v -P '(with-http_secure_link_module|with-http_sub_module|with-http_addition_module|with-http_realip_module|with-http_dav_module|with-http_flv_module|with-http_mp4_module|with-http_random_index_module|with-mail|with-mail_ssl_module|nginx-auth-pam|nginx-dav-ext-module|nginx-echo|nginx-syslog|nginx-cache-purge|ngx_http_pinba_module|ngx_http_substitutions_filter_module|nginx-x-rid-header)' "$a.bak" > $a && \
sed -e "s/^\([ \t]*\)--with-ipv6[ \t]*/$am /" -i $a && \
sed -e "s/^\([ \t]*\)--with-ipv6$/$am/" -i $a && \
sed -e 's/^\([ \t]*\)dh_shlibdeps -a/\1dpkg-shlibdeps -a --dpkg-shlibdeps-params=--ignore-missing-info/' -i $a && \
echo -e "override_dh_shlibdeps:\n        dh_shlibdeps --dpkg-shlibdeps-params=--ignore-missing-info\n" >> $a
echo -e "override_dh_shlibdeps:\n dh_shlibdeps --dpkg-shlibdeps-params=--ignore-missing-info\n" >> $a

