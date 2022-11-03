namespace :db do
  desc "Run migrations"
  task :migrate, [:version] do |t, args|
    require "sequel"
    Sequel.extension :migration
    db = Sequel.connect(ENV.fetch("DATABASE_URL"))
    if args[:version]
      puts "Migrating to version #{args[:version]}"
      Sequel::Migrator.run(db, "db/migrations", target: args[:version].to_i)
    else
      puts "Migrating to latest"
      Sequel::Migrator.run(db, "db/migrations")
    end
  end
  desc "Update membership renewal dates"
  task :update_mbrship_renewal_date do
    require "sequel"
    require "./app/api.rb"
    mbr_ids = DB[:members].select(:id).all
    mbr_ids.each do |mbr_id_hash|
      latest_dues_payment_date  = nil
      if !MemberTracker::Member[mbr_id_hash[:id]].payments.empty?
        MemberTracker::Member[mbr_id_hash[:id]].payments.each do |p|
          if p[:payment_type_id] == 5
            if !latest_dues_payment_date.nil?
              latest_dues_payment_date < p[:ts] ? latest_dues_payment_date = p[:ts] : nil
            else
              latest_dues_payment_date = p[:ts]
            end
          end
        end
        print "set mbr_id: #{mbr_id_hash[:id]} with payment date #{latest_dues_payment_date}?"
        answer = $stdin.gets
        case answer
        when /^y/
          m = MemberTracker::Member[mbr_id_hash[:id]].set(mbrship_renewal_date: latest_dues_payment_date)
          m.save
        when /^n/
          print "skipping #{mbr_id_hash[:id]}\n"
        when /^q/
          break
        end
      else
        puts "mbr_id #{mbr_id_hash[:id]} has no payments"
      end
    end
  end
end