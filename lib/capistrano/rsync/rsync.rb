require "capistrano/scm/plugin"

# By convention, Capistrano plugins are placed in the
# Capistrano namespace. This is completely optional.
module Capistrano
  class Rsync < ::Capistrano::SCM::Plugin
    def set_defaults
      # Define any variables needed to configure the plugin.
      # set_if_empty :myvar, "my-default-value"
      set_if_empty :rsync_options, [
        '--archive'
      ]
      set_if_empty :rsync_copy, "rsync -aAX"

      # Default branch is master
      set_if_empty :branch, "master"

      # Sparse checkout allows to checkout only part of the repository
      set_if_empty :rsync_sparse_checkout, []

      # Merely here for backward compatibility reasons
      set_if_empty :rsync_checkout_tag, false

      # Option states what to checkout
      set_if_empty :rsync_checkout, -> {fetch(:rsync_checkout_tag, false) ? "tag" : "branch"}

      # You may not need the whole history, put to false to get it whole
      set_if_empty :rsync_depth, 1

      # Stage is used on your local machine for rsyncing from.
      set_if_empty :rsync_stage, "scm"

      # Cache is used on the server to copy files to from to the release directory.
      # Saves you rsyncing your whole app folder each time.  If you nil rsync_cache,
      # Capistrano::Rsync will sync straight to the release path.
      # set_if_empty :rsync_cache, File.join("#{fetch(:deploy_to)}", "#{fetch(:rsync_stage)}")

      set_if_empty :rsync_target_dir, "."

      # Creates opportunity to define remote other than origin
      set_if_empty :git_remote, "origin"

      set_if_empty :enable_git_submodules, false

      set_if_empty :reset_git_submodules_before_update, false

      set_if_empty :bypass_git_clone, false

      rsync_target = lambda do
        case fetch(:rsync_checkout)
          when "tag"
            target = "tags/#{fetch(:branch)}"
          when "revision"
            target = fetch(:branch)
          else
            target = "#{fetch(:git_remote)}/#{fetch(:branch)}"
          end
        target
      end
      set :rsync_target, rsync_target

      rsync_branch = lambda do
        if fetch(:rsync_checkout) == "tag"
          branch = "tags/#{fetch(:branch)}"
        else
          branch = fetch(:branch)
        end

        branch
      end
      set :rsync_branch, rsync_branch

      git_depth = lambda do
        depth = !!fetch(:rsync_depth, false) ? "--depth=#{fetch(:rsync_depth)}" : ""
        depth
      end
      set :git_depth, git_depth

      git_depth_clone = lambda do
        depth = !!fetch(:rsync_depth, false) ? "--depth=#{fetch(:rsync_depth)} --no-single-branch" : ""
        depth
      end
      set :git_depth_clone, git_depth_clone
    end

    def define_tasks
      namespace :rsync do

        def has_roles?
          return env.filter(release_roles(:all)).any?
        end

        desc "Check directories on Remote"
        task :check do
          on release_roles :all do
            execute :mkdir, "-p", release_path
            rsync_cache = File.join("#{fetch(:deploy_to)}", "#{fetch(:rsync_stage)}")
            execute :mkdir, "-p", rsync_cache
          end
        end

        desc "Git first time on Local"
        task :create_stage do
          next if File.directory?(fetch(:rsync_stage))
          next if !has_roles?
          next if fetch(:bypass_git_clone)

          if fetch(:rsync_sparse_checkout, []).any?
            run_locally do
              execute :git, :init, '-q', fetch(:rsync_stage)
              within fetch(:rsync_stage) do
                execute :git, :remote, :add, :origin, fetch(:repo_url)

                execute :git, :fetch, '-q --prune --all -t', "#{fetch(:git_depth)}"

                execute :git, :config, 'core.sparsecheckout true'
                execute :mkdir, '.git/info'
                open(File.join(fetch(:rsync_stage), '.git/info/sparse-checkout'), 'a') { |f|
                  fetch(:rsync_sparse_checkout).each do |sparse_dir|
                    f.puts sparse_dir
                  end
                }

                execute :git, :pull, '-q', "#{fetch(:git_depth)}", :origin, "#{fetch(:rsync_branch)}"
              end
            end
          else
            submodules = !!fetch(:enable_git_submodules) ? "--recursive" : ""
            run_locally do
              execute :git,
                :clone,
                '-q',
                fetch(:repo_url),
                fetch(:rsync_stage),
                "#{fetch(:git_depth_clone)}"
                # "#{submodules}"
            end
          end
        end

        desc "Stage the repository in a local directory."
        task :stage => %w[create_stage] do
          next if !has_roles?
          next if fetch(:bypass_git_clone)

          run_locally do
            within fetch(:rsync_stage) do
              execute :git, :fetch, '-q --all --prune', "#{fetch(:git_depth)}"

              if !!fetch(:rsync_checkout_tag, false)
                execute :git, :fetch, '-q --tags'
              end

              execute :git, :reset, '-q', '--hard', "#{fetch(:rsync_target)}"
              execute :git, :checkout, '-q', "#{fetch(:rsync_target)}"

              if fetch(:enable_git_submodules)
                if fetch(:reset_git_submodules_before_update)
                  execute :git, :submodule, :foreach, "'git reset --hard HEAD && git clean -qfd && git fetch -t'"
                end

                execute :git, :submodule, :init
                execute :git, :submodule, :update
              end
            end
          end
        end

        task :stage_done => %w[stage]


        desc "Stage and rsync to the server (or its cache)."
        task :upload => %w[rsync:stage_done] do
          on release_roles(:all) do |role|
            user = role.user + "@" if !role.user.nil?
            rsync_options = fetch(:rsync_options).clone

            if !role.port.nil?
              rsync_options.unshift("-e 'ssh -p #{role.port}'")
            elsif fetch(:ssh_options).fetch(:port)
              rsync_options.unshift("-e 'ssh -p #{fetch(:ssh_options).fetch(:port)}'")
            end
            
            run_locally do
              within fetch(:rsync_stage) do
                rsync_cache = File.join("#{fetch(:deploy_to)}", "#{fetch(:rsync_stage)}")
                execute :rsync,
                  rsync_options,
                  fetch(:rsync_target_dir),
                  "#{user}#{role.hostname}:#{rsync_cache || release_path}"
              end
            end
          end
        end

        desc 'Locally determine the revision that will be deployed'
        task :set_current_revision do
          next if !has_roles?
          run_locally do
            within fetch(:rsync_stage) do
              rev = capture(:git, 'rev-parse', 'HEAD').strip
              set :current_revision, rev
            end
          end
        end

        desc "Copy the code to the releases directory."
        task :release => %w[upload] do
          # Skip copying if we've already synced straight to the release directory.
          # next if !fetch(:rsync_cache)
          next if !has_roles?

          rsync_cache = File.join("#{fetch(:deploy_to)}", "#{fetch(:rsync_stage)}")
          copy = %(#{fetch(:rsync_copy)} "#{rsync_cache}/" "#{release_path}/")
          on release_roles(:all) do |host|
            execute copy
          end
        end

        task :create_release => %w[release]

      end
    end

    def register_hooks
      after "deploy:new_release_path", "rsync:check"
      after "deploy:new_release_path", "rsync:create_release"
      before "deploy:set_current_revision", "rsync:set_current_revision"
    end

  end
end
