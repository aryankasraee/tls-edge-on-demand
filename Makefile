.PHONY: test up drill down
test:
	cd ask && python3 -m unittest -v
up:
	docker compose up -d
drill:
	scripts/drill.sh
down:
	docker compose down -v
