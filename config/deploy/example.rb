# example configuration
set :deploy_to, "/var/www/example"

# linux backends
server 'host', user: 'example', roles: %w{workers}

# directories setup
append :dirs, "#{fetch(:deploy_to)}/run/workers"
append :dirs, ["#{fetch(:deploy_to)}/run/logs", 777]

# commands setup
append :commands, "mv public/content public/content.scm"

# symlinks setup
append :symlinks, ['/var/www/static/public/content', 'public/content']

# symlinks shared run
append :symlinks, ["#{fetch(:deploy_to)}/run/logs", 'logs']

# command after release current symlink
append :release_commands, "apachectl reload"
