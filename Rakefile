namespace :mbr do
  desc "Backfill mbr_since from earliest dues payment for members where mbr_since is NULL"
  task :backfill_mbr_since do
    require "sequel"
    require "./app/api.rb"
    dues_type = DB[:payment_types].first(type: 'Dues')
    abort "ERROR: 'Dues' payment type not found in payment_types table" if dues_type.nil?
    dues_type_id = dues_type[:id]
    members = DB[:members].where(mbr_since: nil).select(:id, :fname, :lname, :callsign).all
    puts "Found #{members.count} member(s) with mbr_since = NULL"
    updated = 0
    skipped = 0
    members.each do |m|
      first_payment = DB[:payments]
        .where(mbr_id: m[:id], payment_type_id: dues_type_id)
        .order(:ts)
        .first
      if first_payment.nil?
        puts "  SKIP  id=#{m[:id]} #{m[:lname]}, #{m[:fname]} (#{m[:callsign]}) — no dues payment found"
        skipped += 1
      else
        since_date = first_payment[:ts].to_date
        DB[:members].where(id: m[:id]).update(mbr_since: since_date)
        puts "  SET   id=#{m[:id]} #{m[:lname]}, #{m[:fname]} (#{m[:callsign]}) — mbr_since = #{since_date}"
        updated += 1
      end
    end
    puts "\nDone. Updated: #{updated}, Skipped (no dues payment): #{skipped}"
  end

  desc "Close open non-renewal followup actions for members whose membership is currently paid up"
  task :close_stale_non_renewal_followups, [:auth_user_id] do |_t, args|
    require "sequel"
    require "./app/api.rb"
    auth_user_id = (args[:auth_user_id] || 22).to_i
    nrf_type_id   = MemberTracker::MemberActionType[name: 'non_renew_followup'].id
    log_action_id = MemberTracker::Action.get_action_id('member_not_renew_followup')
    open_actions  = DB[:member_actions]
                      .where(member_action_type_id: nrf_type_id, completed: false)
                      .all
    if open_actions.empty?
      puts "No open non-renewal followup actions found."
      next
    end
    closed = 0
    open_actions.each do |ma|
      mbr = MemberTracker::Member[ma[:member_target]]
      next if mbr.nil?
      next if mbr.mbrship_renewal_date.nil?
      next unless mbr.mbrship_renewal_date.to_date.next_year > Date.today
      puts "Closing action id=#{ma[:id]} for member #{mbr.fname} #{mbr.lname} (id=#{mbr.id})"
      DB.transaction do
        DB[:member_actions].where(id: ma[:id]).update(completed: true)
        MemberTracker::Log.new(
          mbr_id:        ma[:member_target],
          a_user_id:     auth_user_id,
          ts:            Time.now,
          action_id:     log_action_id,
          mbr_action_id: ma[:id],
          notes:         "Non-renewal followup auto-completed: member is currently paid up (retroactive cleanup)"
        ).save
      end
      closed += 1
    end
    puts "Done. Closed #{closed} action(s)."
  end

  desc "One-time scan of existing members for possible duplicates, using the same fuzzy-match validator as member create/update"
  task :find_duplicates do
    require "sequel"
    require "./app/api.rb"
    members = MemberTracker::Member.select(:id, :fname, :lname, :email, :callsign).order(:id).all
    puts "Scanning #{members.count} members for possible duplicates..."
    pairs_found = 0
    members.each do |m|
      matches = MemberTracker::Member.find_possible_duplicates(
        { fname: m.fname, lname: m.lname, email: m.email, callsign: m.callsign },
        exclude_id: m.id
      )
      matches.each do |match|
        next unless match.id > m.id # report each pair once, regardless of which side found it
        pairs_found += 1
        puts "-" * 60
        puts "  id=#{m.id}\t#{m.fname} #{m.lname}\tcallsign=#{m.callsign.inspect}\temail=#{m.email.inspect}"
        puts "  id=#{match.id}\t#{match.fname} #{match.lname}\tcallsign=#{match.callsign.inspect}\temail=#{match.email.inspect}"
      end
    end
    puts "-" * 60
    puts "Done. Found #{pairs_found} possible duplicate pair(s) among #{members.count} members."
    puts "This is a read-only report -- no records were changed. Review each pair and merge/correct manually via /m/member/edit/:id."
  end

  desc "One-time: normalize existing members' email/callsign to the canonical placeholder values"
  task :normalize_identity_placeholders do
    require "sequel"
    require "./app/api.rb"

    historical_emails = MemberTracker::Member::EXCLUDED_PLACEHOLDER_EMAILS -
      [MemberTracker::Member::NO_EMAIL_PLACEHOLDER]
    all_members = DB[:members].select(:id, :email, :callsign).all

    email_target_ids = all_members.select { |m|
      m[:email].to_s.strip.empty? || historical_emails.include?(m[:email].to_s.strip.upcase)
    }.map { |m| m[:id] }
    callsign_target_ids = all_members.select { |m| m[:callsign].to_s.strip.empty? }.map { |m| m[:id] }

    puts "#{email_target_ids.size} member(s) will have email set to #{MemberTracker::Member::NO_EMAIL_PLACEHOLDER} (email_bogus=true)"
    puts "#{callsign_target_ids.size} member(s) will have callsign set to #{MemberTracker::Member::NO_CALLSIGN_PLACEHOLDER}"
    print "Proceed? (y/n) "
    answer = $stdin.gets
    unless answer && answer.strip.downcase == 'y'
      puts "Aborted, no changes made."
      next
    end

    DB.transaction do
      unless email_target_ids.empty?
        DB[:members].where(id: email_target_ids).update(email: MemberTracker::Member::NO_EMAIL_PLACEHOLDER, email_bogus: true)
      end
      unless callsign_target_ids.empty?
        DB[:members].where(id: callsign_target_ids).update(callsign: MemberTracker::Member::NO_CALLSIGN_PLACEHOLDER)
      end
    end
    puts "Done. Updated #{email_target_ids.size} email(s) and #{callsign_target_ids.size} callsign(s)."
  end

  desc "READ-ONLY: itemize every DB record tied to a set of member ids, to inform manual duplicate consolidation via psql"
  task :itemize_records, [:id1] do |t, args|
    require "sequel"
    require "./app/api.rb"

    # Rake splits comma-separated bracket args into positional args, not a
    # single string -- args[:id1] catches the first, args.extras catches the
    # rest, so `rake mbr:itemize_records[951,891,646]` works as expected.
    ids = ([args[:id1]] + args.extras).compact.reject(&:empty?).map(&:to_i)
    if ids.empty?
      abort "Usage: rake mbr:itemize_records[id1,id2,id3]  (or quote it: \"rake mbr:itemize_records[id1,id2,id3]\")"
    end

    # NOT NULL means that table's FK column can never be left pointing at a
    # deleted member -- it must be reassigned to the id you're keeping (or
    # that row deleted/handled) before `DELETE FROM members` will succeed.
    # nullable columns give you a choice: reassign to preserve attribution,
    # or set NULL if it doesn't matter. All ten of these FKs are defined
    # ON DELETE NO ACTION, so Postgres itself will refuse the final member
    # delete (naming the exact constraint) if anything's still missed --
    # there's no silent-corruption risk from doing this out of order, just
    # a blocked DELETE with a clear error.
    NOT_NULL = " [NOT NULL -- must reassign]".freeze
    NULLABLE = " [nullable -- reassign or set NULL]".freeze

    events_by_id = {}
    units_by_id  = {}

    ids.each do |id|
      puts "=" * 70
      m = DB[:members].where(id: id).first
      if m.nil?
        puts "Member id=#{id}: NOT FOUND"
        next
      end
      puts "Member id=#{id}  #{m[:fname]} #{m[:lname]}  callsign=#{m[:callsign].inspect}  email=#{m[:email].inspect}"
      puts "  mbr_type=#{m[:mbr_type]}  mbr_since=#{m[:mbr_since]}  renewal_date=#{m[:mbrship_renewal_date]}  email_bogus=#{m[:email_bogus]}"
      puts "-" * 70

      au = DB[:auth_users].where(mbr_id: id).all
      puts "  auth_users (#{au.size})#{NOT_NULL}:"
      au.each { |r| puts "    id=#{r[:id]}  role_id=#{r[:role_id]}  last_login=#{r[:last_login]}" }

      pay = DB[:payments].where(mbr_id: id).order(:ts).all
      puts "  payments (#{pay.size})#{NOT_NULL}:"
      pay.each { |r| puts "    id=#{r[:id]}  ts=#{r[:ts]}  payment_type_id=#{r[:payment_type_id]}  amount=#{r[:payment_amount]}" }

      logs = DB[:logs].where(mbr_id: id).order(:ts).all
      puts "  logs (#{logs.size})#{NULLABLE}:"
      logs.each { |r| puts "    id=#{r[:id]}  ts=#{r[:ts]}  action_id=#{r[:action_id]}  notes=#{r[:notes].to_s[0,60].inspect}" }

      renewals = DB[:mbr_renewals].where(mbr_id: id).order(:ts).all
      puts "  mbr_renewals (#{renewals.size})#{NOT_NULL}:"
      renewals.each { |r| puts "    id=#{r[:id]}  ts=#{r[:ts]}  renewal_event_type_id=#{r[:renewal_event_type_id]}" }

      targeted = DB[:member_actions].where(member_target: id).all
      puts "  member_actions as target (#{targeted.size})#{NOT_NULL}:"
      targeted.each { |r| puts "    id=#{r[:id]}  type_id=#{r[:member_action_type_id]}  completed=#{r[:completed]}  ts=#{r[:ts]}" }

      tasked = DB[:member_actions].where(tasked_to_mbr_id: id).all
      puts "  member_actions tasked to this member (#{tasked.size})#{NULLABLE}:"
      tasked.each { |r| puts "    id=#{r[:id]}  target_member=#{r[:member_target]}  type_id=#{r[:member_action_type_id]}  completed=#{r[:completed]}" }

      events = DB[:events].where(mbr_id: id).all
      puts "  events (organized/contact) (#{events.size})#{NOT_NULL}:"
      events.each { |r| puts "    id=#{r[:id]}  name=#{r[:name]}  ts=#{r[:ts]}" }

      attended = DB[:members_events].where(mbr_id: id).all.map { |r| r[:event_id] }
      events_by_id[id] = attended
      puts "  members_events (attendee of #{attended.size} event(s))#{NOT_NULL}, part of a composite primary key -- see overlap check below: #{attended}"

      units = DB[:members_units].where(mbr_id: id).all.map { |r| r[:unit_id] }
      units_by_id[id] = units
      puts "  members_units (member of #{units.size} unit(s))#{NOT_NULL}, part of a composite primary key -- see overlap check below: #{units}"

      audit = DB[:audit_logs].where(mbr_id: id).order(:changed_date).all
      puts "  audit_logs (#{audit.size})#{NULLABLE}:"
      audit.each { |r| puts "    id=#{r[:id]}  changed_date=#{r[:changed_date]}  column=#{r[:column]}  #{r[:old_value].inspect} -> #{r[:new_value].inspect}" }
    end

    puts "=" * 70
    puts "Overlap check (members_events / members_units) -- these two tables use a"
    puts "composite primary key of (event_id/unit_id, mbr_id), so reassigning a row"
    puts "to an id that already has the same event/unit will violate that key. If"
    puts "any pairs are listed below, DELETE the redundant row for the id you're"
    puts "retiring instead of UPDATE-ing it for that specific event/unit id."
    found = ids.select { |i| events_by_id[i] }
    overlap_found = false
    found.combination(2).each do |a, b|
      shared_events = (events_by_id[a] & events_by_id[b])
      shared_units  = (units_by_id[a] & units_by_id[b])
      if !shared_events.empty?
        overlap_found = true
        puts "  members_events: ids #{a} and #{b} both attended event_id(s) #{shared_events}"
      end
      if !shared_units.empty?
        overlap_found = true
        puts "  members_units: ids #{a} and #{b} are both in unit_id(s) #{shared_units}"
      end
    end
    puts "  none found" unless overlap_found

    puts "=" * 70
    puts "This is a read-only report -- no records were changed."
    puts "Suggested order once you've decided which id to keep:"
    puts "  1. members_events / members_units -- delete the retiring id's row for"
    puts "     any event/unit flagged in the overlap check above, then reassign"
    puts "     mbr_id -> keeper for the rest."
    puts "  2. The other NOT NULL tables (payments, mbr_renewals,"
    puts "     member_actions.member_target, events.mbr_id, auth_users.mbr_id) --"
    puts "     reassign mbr_id/member_target to the keeper. auth_users is a judgment"
    puts "     call: decide whether to reassign the login or delete it outright."
    puts "  3. The nullable tables (logs, audit_logs, member_actions.tasked_to_mbr_id)"
    puts "     -- reassign to preserve attribution, or set NULL if it doesn't matter."
    puts "  4. DELETE FROM members WHERE id = <retiring id>. Every FK here is"
    puts "     ON DELETE NO ACTION, so this will simply fail with a clear error"
    puts "     naming the constraint if anything above was missed."
  end
end

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
    start_date = DateTime.now
    payments.where(payment_type_id: 5).each do |pmt|
      if (start_date - 365) < pmt[:ts].to_datetime
        log_ids << [pmt[:mbr_id], pmt[:log_id]]
      end
    end
    mbr_codes = []
    log_ids.each do |logid|
      note_to_test = logs.first(id: logid[1])[:notes]
      lines_from_log_notes = nil
      topics, freq, modes = nil
      question_h = {topic: [], freq: [], mode: []}
      active_q = nil
      cont_from_q = false #needed bc may incorrectly copy survey from email
      if /^.*jotform/.match(note_to_test)
        lines_from_log_notes = note_to_test.split("\n")
        capture = false
        lines_from_log_notes.each do |line|
          if (/^.*jotform/.match(line) && capture == false)
            capture = true
          elsif capture == true
            if /^What/.match(line)
              cont_from_q = true
            end
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
              if cont_from_q == true
                if !/^\*\*/.match(line)
                  question_h[active_q] << line.strip
                else
                  break
                end
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
          mbr_codes << [logid[1],logid[0],codes]
        else
          puts "nothing found"
        end
      end
    end
    mbr_codes.each do |q_array|
      puts "logId: #{q_array[0]}, mbrid: #{q_array[1]}, codes: #{q_array[2]}"
    end
  end
  desc "Removing whitespace from emails"
  task :mbrship_email_clean do
    #script to apply latest dues payment date to members#mbrship_renewal_date
    require "sequel"
    require "./app/api.rb"
    mbrs = DB[:members]
    mbrs.each do |mbr|
      if /^\s/.match(mbr[:email])
        tmp_email = mbr[:email].lstrip!
        mbrs.where(id: mbr[:id]).update(email: tmp_email)
        #DB[:members].first(id: mbr[:id]).update(email: tmp_email)
        puts "got it: #{tmp_email}"
      end
    end
  end
  desc "Find members who requested a call"
  task :find_call_requests do
    #script to find members who requested a call
    require "sequel"
    require "./app/api.rb"
    payments = DB[:payments]
    logs = DB[:logs]
    log_ids = []
    payments.where(payment_type_id: 5).each do |pmt|
      #search for corresponding log entry
      if logs[id: pmt[:log_id]][:notes] =~ /der\?\s+Yes/
        log_ids << pmt[:log_id]
      end
    end
    puts "logs from dues payments with mbrs requesting a call #{log_ids}"
  end
  desc "Find members who did not renew"
  task :find_non_renewing_mbrs do
    #script to find members who did not renew
    require "sequel"
    require "./app/api.rb"
    #use mbr_renewals table
    mbr_renewals = DB[:mbr_renewals].select(:mbr_id, :ts).where(renewal_event_type_id: 8)
    mbr_renewals.each do |mbr|
      #add to member_actions table if mbr_renewals[:ts > DateTime.now - 365]
      count = 1
      if mbr[:ts].to_date > DateTime.now.to_date - 365
        #check if member action already exists member_action_type_id: 3 is non_renew_followup
        mbr_action = DB[:member_actions].where(member_target: mbr[:mbr_id], member_action_type_id: 3).first
        if mbr_action.nil?
          #get user input to confirm
          puts "Insert non-renewal action for member #{mbr[:mbr_id]}? (y/n/q)"
          answer = $stdin.gets.strip.downcase
          case answer
          when 'y'
          #insert new member action
          DB[:member_actions].insert(a_user_id: 22, member_target: mbr[:mbr_id], member_action_type_id: 3,
          notes: "Member did not renew, mass data entry: #{count}", completed: false, ts: mbr[:ts])
          puts "Inserted non-renewal action for member #{mbr[:mbr_id]}"
          count += 1
          when 'n'
            puts "Skipping member #{mbr[:mbr_id]}"
          when 'q'
            puts "Exiting"
            break
          else
            puts "Invalid input, please enter y/n/q"
          end
        else
          puts "Member action already exists for member #{mbr[:mbr_id]}"
        end
      end
    end
  end
end
#methods available to tasks
def categorize(answer_str, question_symbol)
  #returns a category(type:string) for the answer string
  return_code = nil
  case question_symbol
  when :topic
    h = {T1: /^Portable Oper/, T2: /^Contest/, T3: /^Beginner op/, T4: /^Technical/, T5: /^Product De/,
    T6: /^Radio Hi/, T7: /^Distance Com/, T8: /^Digital Mode/, T9: /^Propagation/, T10: /^Emergency prep/}
    h.each do |k,v|
      if v.match(answer_str)
        return_code = k.to_s
      end
    end
    if return_code.nil?
      #this is 'other'
      return_code = "T11"
    end
  when :freq
    h = {F1: /^Hig/, F2: /^VHF/, F3: /^Mic/, F4: /^Low/, F5: /^Non/}
    h.each do |k,v|
      if v.match(answer_str)
        return_code = k.to_s
      end
    end
  when :mode
    h = {M1: /^Voice/, M2: /^CW/, M3: /^Digital/, M4: /^None/}
    h.each do |k,v|
      if v.match(answer_str)
        return_code = k.to_s
      end
    end
    if return_code.nil?
      #this is 'other'
      return_code = "F5"
    end
  else
    puts "oops"
  end
  return_code
end
