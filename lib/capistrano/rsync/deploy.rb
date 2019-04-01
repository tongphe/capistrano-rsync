set_if_empty :start_time, Time.now  
set_if_empty :shared_stage, 'shared'
set_if_empty :hotfix_stage, 'hotfix'

after 'deploy:failed', :deploy_failed do
  puts 'Deployment failed: checking failed release...'
  on release_roles(:all) do |role|
    # check if symlink:release was performed for failed release to rollback symlink 
    if test "[ `readlink #{current_path}` == #{release_path} ]"
      last_release = capture(:ls, "-xt", releases_path).split
      if last_release.count < 2
        puts "Can't rollback symlink, last release does not exist!"
        exit 1
      end
      last_release_path = releases_path.join(last_release[-2])
      puts "Rollback symlink to last good release #{last_release_path}"
      tmp_current_path = releases_path.join(current_path.basename)
      execute :ln, "-s", last_release_path, tmp_current_path
      execute :mv, tmp_current_path, current_path.parent
    end
    # validate release_path for deletion
    if release_path == current_path
      puts "Release path is invalid, nothing to remove!"
    # symlink:release was not performed and safe to remove failed release
    else
      puts "Remove failed release!"
      execute :rm, '-rf', release_path
    end
    # checking if missing current link
    if test "[ ! -e #{current_path} ]"
      last_release = capture(:ls, "-xt", releases_path).split
      last_release_path = releases_path.join(last_release[-1])
      puts "Missing current link, symlink to last good release!"
      tmp_current_path = releases_path.join(current_path.basename)
      execute :ln, "-s", last_release_path, tmp_current_path
      execute :mv, tmp_current_path, current_path.parent
    end
  end
end

before 'deploy:cleanup_rollback', :finish_rollback do
  puts "Checking if current link is missing..."
  on release_roles(:all) do |role|
    if test "[ ! -e #{current_path} ]"
      last_release = capture(:ls, "-xt", releases_path).split
      last_release_path = releases_path.join(last_release[-2])
      puts "Missing current link, symlink to last good release!"
      tmp_current_path = releases_path.join(current_path.basename)
      execute :ln, "-s", last_release_path, tmp_current_path
      execute :mv, tmp_current_path, current_path.parent
    end
  end
  next if fetch(:rollback_commands).nil? || fetch(:rollback_commands).empty?
  on release_roles(:all) do |role|
    fetch(:rollback_commands).each do |cmd|
      execute("cd " + fetch(:deploy_to) + " && " + cmd)
    end
  end  
end

namespace :deploy do

  desc 'Make directories'
  task :prepare_dir do
    next if fetch(:dirs).nil? || fetch(:dirs).empty?
    on release_roles(:all) do |role|
      fetch(:dirs).each do |dir|
        within release_path do
          if dir.kind_of?(Array)
              dir_path = dir[0][0] == '/' ? dir[0] : File.join(release_path.to_s, dir[0])
            if !test("[ -e #{dir_path} ]")
              execute :mkdir, '-p', dir_path
            end
            execute :chmod, dir[1], dir_path
          else
            dir_path = dir[0] == '/' ? dir : File.join(release_path.to_s, dir)
            if !test("[ -e #{dir_path} ]")
              execute :mkdir, '-p', dir_path
            end
          end
        end
      end
    end
  end

  desc "Graceful restart laravel worker"
  task :restart_worker_laravel do
    on release_roles(:worker) do
      releases = capture(:ls, "-xt", releases_path).split
      releases.each do |r|
        r_path = releases_path.join(r)
        within r_path do
          execute :php, 'artisan', 'queue:restart'
        end
      end
    end
  end

  desc 'Symlinks in release path'
  task :prepare_symlink do
    next if fetch(:symlinks).nil? || fetch(:symlinks).empty?
    on release_roles(:all) do |role|
      fetch(:symlinks).each do |link|
        within release_path do
          source = link[0] 
          target = link[1]
          execute :ln, '-s', source, target
        end
      end
    end
  end

  desc "Run commands before symlink release"
  task :prepare_command do
    next if fetch(:commands).nil? || fetch(:commands).empty?
    on release_roles(:all) do |role|
      fetch(:commands).each do |cmd|
        execute("cd " + release_path.to_s + " && " + cmd)
      end
    end
  end

  desc "Run commands after symlink release"
  task :release_command do
    next if fetch(:release_commands).nil? || fetch(:release_commands).empty?
    on release_roles(:all) do |role|
      fetch(:release_commands).each do |cmd|
        execute("cd " + release_path.to_s + " && " + cmd)
      end
    end
  end

  desc "Run unittest on first remote server"
  task :unittest do
    next if fetch(:unittest).nil? || fetch(:unittest).empty?
    first_server = true
    on release_roles(:all) do |role|
      next if !first_server
      fetch(:unittest).each do |cmd|
        execute("cd " + current_path.to_s + " && " + cmd)
      end
      first_server = false
    end
  end

  desc "Upload shared file to remote servers"
  task :upload_shared do
    on release_roles(:all) do |role|
      port = fetch(:ssh_options).fetch(:port)
      user = role.user + "@" if !role.user.nil?
      rsync_option = "-e 'ssh -p #{port}'" if port
      run_locally do
        execute "rsync #{rsync_option} #{fetch(:rsync_options).join(' ')} #{fetch(:shared_stage)}/ #{user}#{role.hostname}:#{shared_path}/"
      end
    end
  end

  desc "Run commands with shared configs on remote before update shared"
  task :shared_command do
    next if fetch(:shared_commands).nil? || fetch(:shared_commands).empty?
    on release_roles(:all) do |role|
      fetch(:shared_commands).each do |cmd|
        execute("cd " + shared_path.to_s + " && " + cmd)
      end
    end
  end

  desc "Revision and copy shared"
  task :prepare_shared => [:upload_shared, :shared_command] do
    on roles(:all) do
      execute "rsync -aAX #{shared_path}/ #{release_path}/"
    end
  end

  desc "Revision and update shared"
  task :update_shared => [:upload_shared, :shared_command] do
    on roles(:all) do
      execute "rsync -aAX #{shared_path}/ #{current_path}/"
    end
  end

  desc "Deploy a hotfix to remote servers"
  task :hotfix do
    on release_roles(:all) do |role|
      port = fetch(:ssh_options).fetch(:port)
      user = role.user + "@" if !role.user.nil?
      rsync_option = "-e 'ssh -p#{port}'" if port
      run_locally do
        execute "rsync -a #{rsync_option} #{fetch(:hotfix_stage)}/ #{user}#{role.hostname}:#{current_path}/"
      end
    end
  end

  def which(cmd)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each { |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      }
    end
    return nil
  end

  desc "Send deploy notification"
  task :notify do
    servers = roles(:all)
    deploy_time = (Time.now - fetch(:start_time)).round
    subject = "Deploy notification - " + fetch(:application) 
    body = "#{fetch(:application)} commit #{fetch(:current_revision)} has been deployed in #{deploy_time}s on #{servers.length} servers:\n#{servers.join(", ")}\n\nDeploy log attachment:"
    tac = 'tac'
    tac = 'tail -r' if !which 'tac'
    deploy_log = `#{tac} log/capistrano.log | awk 'NR==1,/INFO START/' | #{tac} | grep -v DEBUG`
    deploy_log_file = "log/#{release_timestamp}.log"
    File.write(deploy_log_file, deploy_log)
    run_locally do
      # execute "echo -e 'To: #{fetch(:mail_to).split(' ').join(',')};Subject: #{subject};#{body};;#{deploy_log}' | tr ';' '\\n' | sed 's/^ *//g' | sendmail -t -f #{fetch(:mail_from)}"
      execute "echo -e '#{body}' | tr ';' '\\n' | sed 's/^ *//g' | mail -s '#{subject}' -a #{deploy_log_file} -r #{fetch(:mail_from)} #{fetch(:mail_to)}"
    end
  end

end
