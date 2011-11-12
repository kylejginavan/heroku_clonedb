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
      
      display("Warning: Data in the app '#{app}' will be overwritten and will not be recoverable.")
      
      exit unless confirm

      opts             = parse_database_yml
      database_options = load_database_options(opts)

      dump_name = "#{opts[:database]}.dump"

      display "===== Capture Backup from Heroku...", false
       
      run "heroku pgbackups:capture --expire --app #{app}"

      display "===== Downloading Data Dump...", false

      run "curl -o tmp/#{dump_name} `heroku pgbackups:url --app #{app}`"

      display "===== Deleting database #{opts[:database]}...", false
      
      run "dropdb #{opts[:database]} #{database_options}"

      display "===== Creating database #{opts[:database]}...", false
      
      run "createdb #{opts[:database]} #{database_options}"

      display "===== Restoring database #{opts[:database]} with #{dump_name}...", false
      
      shell "pg_restore -d #{opts[:database]} tmp/#{dump_name} -O --verbose --clean --no-acl --no-owner > /dev/null 2>&1"
      
      display "[OK]"
    end


    private

    def is_root?
      unless File.exists?(Dir.pwd + '/config/database.yml')
        display "app rails not found!, you need stay on the root of one rails app"
        exit
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

  end
end

