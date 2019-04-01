# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'capistrano/rsync/version'

Gem::Specification.new do |gem|
  gem.name          = 'capistrano3-rsync'
  gem.version       = Capistrano::Rsync::VERSION
  gem.summary       = 'Capistrano rsync tasks'
  gem.description   = 'Capistrano rsync tasks '
  gem.authors       = 'Tongphe editor'
  gem.email         = 'tongphe.org@gmail.com'
  gem.homepage      = 'https://github.com/tongphe/capistrano-rsync.git'
  gem.license       = 'Opensource'

  gem.files         = ["capistrano3-rsync.gemspec", "lib/capistrano/rsync/rsync.rb", "lib/capistrano/rsync/deploy.rb", "lib/capistrano/rsync/version.rb"]
  gem.require_paths = ['lib']

  gem.add_dependency 'capistrano', '~> 3.0'
  gem.add_development_dependency 'rake', '~> 10.1'
end
