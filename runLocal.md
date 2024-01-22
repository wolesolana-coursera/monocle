# Running Locally
docker-compose up -d

# After applying Config Change
docker-compose run --rm --no-deps api monocle janitor update-idents --elastic elastic:9200 --config /etc/monocle/config.yaml

# Reset the crawler commit date
docker-compose run --rm --no-deps api monocle janitor set-crawler-commit-date --elastic elastic:9200 --config /etc/monocle/config.yaml --workspace monocle --crawler-name github-coursera --commit-date '2023-07-01'