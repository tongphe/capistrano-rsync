NAME = capistrano-rsync-bladrak

love:
	@echo "Feel like makin' love."

pack:
	gem build $(NAME).gemspec

publish: pack
	gem push $(NAME)-*.gem

clean:
	rm -f *.gem
	
.PHONY: love pack publish
.PHONY: clean
