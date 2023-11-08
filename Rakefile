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
  desc "Testing fill members"
  task :repopulate_db do
    require "sequel"
    require "./app/api.rb"
    members = DB[:members]
    particulars = [{fname: 'test_i', lname: 'tester', email: 'test_i@test.com'},
    {fname: 'test_ii', lname: 'tester', email: 'test_ii@test.com'},
    {fname: 'test_iii', lname: 'tester', email: 'test_iii@test.com'},
    {fname: 'test_iv', lname: 'tester', email: 'test_iv@test.com'},
    {fname: 'test_v', lname: 'tester', email: 'test_v@test.com'}]
    particulars.each do |m|
      members.insert(m)
    end
  end
  desc "Testing remove members"
  task :teardown_db do
    #assumes that member id 205 is ME and auth user 22 is member 205, keep password and mbr 205 intact to login
    require "sequel"
    require "./app/api.rb"
    #need to clear tables in this order
    tables = [:audit_logs, :payments, :logs, :members_events, :events, :members_units, :units]
    tables.each do |t|
      DB[t].delete
    end
    DB[:mbr_renewals].exclude(id: 1).sql.delete
    DB[:members].where(lname: 'tester').delete
  end
  desc "Reading jotform data"
  task :get_jf_data do
    require "sequel"
    require "./app/api.rb"
    payments = DB[:payments]
    logs = DB[:logs]
    log_ids = []
    payments.where(payment_type_id: 5).each do |pmt|
      if DateTime.new(2023,02,01).to_time < pmt[:ts]
        log_ids << [pmt[:mbr_id], pmt[:log_id]]
      end
    end
    mbr_codes = {}
    log_ids.each do |logid|
      note_to_test = logs.first(id: logid[1])[:notes]
      lines_from_log_notes = nil
      topics, freq, modes = nil
      question_h = {topic: [], freq: [], mode: []}
      active_q = nil
      if /^.*jotform/.match(note_to_test)
        lines_from_log_notes = note_to_test.split("\n")
        capture = false
        lines_from_log_notes.each do |line|
          if (/^.*jotform/.match(line) && capture == false)
            capture = true
          elsif capture == true
            #have 3 questions topics, freq, mode with variable number of lines following each answer
            if /topics/.match(line)
              active_q = :topic
              m = /.*\?(.*)/.match(line)
              question_h[active_q] << m[1].strip
            elsif /freq/.match(line)
              active_q = :freq
              m = /.*\?(.*)/.match(line)
              question_h[active_q] << m[1].strip
            elsif /mode/.match(line)
              active_q = :mode
              m = /.*\?(.*)/.match(line)
              question_h[active_q] << m[1].strip
            else
              if !/^\*\*/.match(line)
                question_h[active_q] << line.strip
              end
            end
          end
        end
        if !question_h[active_q].empty?
          codes = []
          question_h[:topic].each do |topic|
            codes << categorize(topic, :topic)
          end
          question_h[:freq].each do |freq|
            codes << categorize(freq, :freq)
          end
          question_h[:mode].each do |mode|
            codes << categorize(mode, :mode)
          end
          mbr_codes[logid[0]] = codes
        else
          puts "nothing found"
        end
      end
    end
    mbr_codes.each do |k,v|
      puts "id: #{k}, codes: #{v}"
    end
  end
end
#methods available to tasks
def categorize(answer_str, question_symbol)
  #returns a category(type:string) for the answer string
  return_code = nil
  case question_symbol
  when :topic
    h = {T1: /^Port/, T2: /^Con/, T3: /^Beg/, T4: /^Tec/, T5: /^Prod/, T6: /^Rad/, T7: /^Dis/, T8: /^Dig/,
    T9: /^Prop/, T10: /^Eme/, T11: /^Oth/}
    h.each do |k,v|
      if v.match(answer_str)
        return_code = k.to_s
      end
    end
  when :freq
    h = {F1: /^Hig/, F2: /^VHF/, F3: /^Mic/, F4: /^Low/, F5: /^Non/}
    h.each do |k,v|
      if v.match(answer_str)
        return_code = k.to_s
      end
    end
  when :mode
    h = {M1: /^Voi/, M2: /^CW/, M3: /^Dig/, M4: /^Non/, M5: /^Oth/}
    h.each do |k,v|
      if v.match(answer_str)
        return_code = k.to_s
      end
    end
  else
    puts "oops"
  end
  return_code
end