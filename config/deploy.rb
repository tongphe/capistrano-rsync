# config valid only for Capistrano 3.7+

set :application, "Example"
set :repo_url, "https://github.com/tongphe/capistrano-rsync.git"
set :mail_from, "deploy@example.com"
set :mail_to, "alerts@example.com"
set :ssh_options, {
  port: 8022
}
set :rsync_options, %w[
  --recursive --delete --delete-excluded
  --exclude .git*
]

after "deploy:updated", "deploy:prepare_dir"
after "deploy:updated", "deploy:prepare_shared"
after "deploy:updated", "deploy:prepare_command"
after "deploy:updated", "deploy:prepare_symlink"
after "deploy:finishing", "deploy:release_command"
