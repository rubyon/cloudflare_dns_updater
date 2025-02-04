FROM ruby:3.4

ENV TZ=Asia/Seoul \
    CLOUDFLARE_API_TOKEN="" \
    CLOUDFLARE_ZONE_ID="" \
    CLOUDFLARE_DOMAINS="" \
    CHECK_INTERVAL_S="10"

WORKDIR /app

COPY . /app

CMD ["ruby", "cloudflare_dns_updater.rb"]
