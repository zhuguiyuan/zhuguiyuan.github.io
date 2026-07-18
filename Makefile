show:
	uv run mkdocs serve

push:
	uv run mkdocs gh-deploy --force

clean:
	rm -rf site

.PHONY: show push clean
