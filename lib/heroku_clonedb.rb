=begin
Copyright (c) 2011 Kyle J. Ginavan & Mauro Torres.  AU!!!

  This file is part of Heroku CloneDB Plugin.

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

module Heroku::Command
  class CloneDB < Db
    def index
      
      is_root?

      opts             = parse_database_yml
      database_options = load_database_options(opts)
      dump_name        = "#{opts[:database]}.dump"
      
      from_app = extract_option("--from")
      from_url = extract_option("--from-url")
      to_app   = extract_option("--to")
      
      
      if from_app.nil? && from_url.nil? && to_app.nil?
        raise(CommandFailed, help)
      end

      if from_app && to_app
        
        has_pgbackups_addon?(from_app)
        has_pgbackups_addon?(to_app)

        display "===== Capture Backup from #{from_app}...", false

        run "heroku pgbackups:capture --expire --app #{from_app}"

        display "===== Transfering data from #{from_app} to #{to_app}...", false

        system "heroku pgbackups:restore DATABASE `heroku pgbackups:url --app #{from_app}` --app #{to_app}"

      elsif from_app

        has_pgbackups_addon?(from_app)

        display("Warning: Data in the local db '#{opts[:database]}' will be overwritten and will not be recoverable with data #{from_app} app.")

        exit unless confirm

        display "===== Capture Backup from #{from_app} app...", false

        run "heroku pgbackups:capture --expire --app #{from_app}"

        display "===== Downloading Data Dump...", false

        run "curl -o tmp/#{dump_name} `heroku pgbackups:url --app #{from_app}`"

        display "===== Restoring database #{opts[:database]} with #{dump_name}...", false
      
        shell "pg_restore -d #{opts[:database]} tmp/#{dump_name} -O --verbose --clean --no-acl --no-owner > /dev/null 2>&1"
        shell "rm -f tmp/#{dump_name}"
      
        display "[OK]"

      elsif to_app && from_url

        has_pgbackups_addon?(to_app)

        display "===== Loading data to #{to_app} app from url...", false
      
        system "heroku pgbackups:restore DATABASE '#{from_url}' --app #{to_app}"

      end
    end

    def dump
      is_root?

      from_app = extract_option("--from")

      raise(CommandFailed, "No --from app specified.\nYou need define --from <app name>") unless from_app

      has_pgbackups_addon?(from_app)

      #define vars
      opts             = parse_database_yml
      dump_name        = "#{opts[:database]}-#{Date.today.to_s}.dump"

      shell "heroku pgbackups:capture --expire --app #{from_app}"

      if dir = extract_option("--dir")
        run "curl -o #{dir}/#{dump_name} `heroku pgbackups:url --app #{from_app}`"
        display "The dump is #{dir}/#{dump_name}", false
      else
        run "curl -o #{dump_name} `heroku pgbackups:url --app #{from_app}`"
        display "You can found the dump in #{dump_name}", false
      end
      puts ""
    end

    private

    def is_root?
      unless File.exists?(Dir.pwd + '/config/database.yml')
        display "app rails not found!, you need stay on the root of one rails app"
        exit
      end
    end
    
    def has_pgbackups_addon?(app_option = nil)
      app_option = app_option ? app_option : app
      pgbackups_addon = "pgbackups"
      unless heroku.installed_addons(app_option).select{|addon| addon["name"].match(/pgbackups/)}.first
        display "Adding #{pgbackups_addon} to #{app_option}... ", true
        heroku.install_addon(app_option, pgbackups_addon, {})
      end
    end

    def run(cmd)
      shell cmd
      if $?.exitstatus == 0
        display "[OK]"
      else
        display "[FAIL]"
      end
    end

    def load_database_options(conf)
      opts = ""
      opts << " -h #{conf[:host]} " if conf[:host]
      opts << " -p #{conf[:port]} " if conf[:port]
      opts << "-U #{conf[:username]}" if conf[:username]
      opts << "-w #{conf[:password]}" if conf[:password]      
      return opts
    end

    def parse_database_yml
      return "" unless File.exists?(Dir.pwd + '/config/database.yml')

      environment = ENV['RAILS_ENV'] || ENV['MERB_ENV'] || ENV['RACK_ENV']
      environment = 'development' if environment.nil? or environment.empty?

      conf = YAML.load(File.read(Dir.pwd + '/config/database.yml'))[environment]
      database_hash = {:database => conf['database'], :username => conf['username'], :password => conf['password'],
                       :host => conf['host']}
      database_hash.merge!(:port => conf['port']) if conf['port']
      return database_hash
    rescue Exception => ex
      puts "Error parsing database.yml: #{ex.message}"
      puts ex.backtrace
      ""
    end

    def extract_option(options, default=true)
      values = options.is_a?(Array) ? options : [options]
      return unless opt_index = args.select { |a| values.include? a }.first
      opt_position = args.index(opt_index) + 1
      if args.size > opt_position && opt_value = args[opt_position]
        if opt_value.include?('--')
          opt_value = nil
        else
          args.delete_at(opt_position)
        end
      end
      opt_value ||= default
      args.delete(opt_index)
      block_given? ? yield(opt_value) : opt_value
    end

    def help
help = <<EOF
For load a data dump from heroku app to localhost:

    $ heroku clonedb --from app_name

For transfer data from one app to another:

    $ heroku clonedb --from app_name1 --to app_name2

For transfer data from url dump to heroku app:

    $ heroku clonedb --from-url 'http://s3.amazonaws.com/.....mydb.dump?authparameters' --to app_name

For get a data dump from heroku app:

    $ heroku clonedb:dump --from app_name [--dir <dir_path>]

EOF
      help
    end

  end
end

