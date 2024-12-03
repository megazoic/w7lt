require_relative '../config/sequel'

module MemberTracker
  class Member < Sequel::Model
    one_to_one :auth_user, :class=>"MemberTracker::Auth_user", key: :mbr_id
    one_to_many :logs, :class=>"MemberTracker::Log", key: :mbr_id
    many_to_many :units, left_key: :mbr_id, right_key: :unit_id, join_table: :members_units
    many_to_many :events, left_key: :mbr_id, right_key: :event_id, join_table: :members_events
    one_to_many :payments, :class=>"MemberTracker::Payment", key: :mbr_id
    one_to_many :audit_logs, :class=>"MemberTracker::AuditLog", key: :mbr_id
    many_to_one :refer_types, :class=>"MemberTracker::ReferType", key: :refer_type_id
    #keep sk last so can remove for payment route
    @mbr_types = ['family', 'student', 'full', 'honorary', 'none', 'sk']
    @modes = {'1' => 'phone', '2' => 'cw', '3' => 'rtty', '4' => 'msk:ft8/jt65', '5' => 'digital:other',
      '6' => 'packet', '7' => 'psk31/63', '8' => 'video:sstv', '9' => 'mesh network'}
    class << self
      attr_reader :mbr_types, :modes
    end

    def record(member_data)
      unless member_data.key?('lname')
        message = 'Invalid member: \'lname\' is required'
        return RecordResult.new(false, nil, message)
      end
      member = Member.new(member_data)
      member.save
      RecordResult.new(true, member.id, nil)
    end
    def members_with_lastname(name)
      matching_members = Member.where(lname: name).all
      matching_members
      #data_out = []
      #matching_members.each {|m| data_out << m.values}
      #data_out
    end
    def validate_dupes(guest_to_test)
      #expecting guests_to_test is hash containing at least 2/3 [:fname, :lname, :callsign]
      #mbrs = Member.select(:fname, :lname, :callsign, :email).all
      #first, need to make sure hash is in correct format
      need_to_transform = false
      guest_to_test.each do |k,v|
        if k.is_a?(String)
          need_to_transform = true
        end
      end
      if need_to_transform == true
        guest_to_test.transform_keys!(&:to_sym)
      end
      dupe_member = Member.where(guest_to_test).first
      if !dupe_member.nil?
        return dupe_member.id
      end
      return 0
    end
    def get_jf_data
      #returns members and their answers on jotform renewal in form {mbr_id: int, codes: ["T1", "F1"],
      # log_id: int}
      #where T, F and M correspond to sections in jotform survey Topics, Frequencies, Modes
      #only members who have submitted new and renewing memberships within the last year are included
        payments = DB[:payments]
        logs = DB[:logs]
        log_ids = []
        start_date = DateTime.now
        other = {:topics=>[], :modes=>[]}
        payments.where(payment_type_id: 5).each do |pmt|
          if  (start_date - 365) < pmt[:ts].to_datetime
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
                #there is 'other' choice with textbox response. Grab this
                topic_response = categorize_survey(topic, :topic)
                if /^T11\|/.match(topic_response)
                  codes << "T11"
                  other[:topics] << topic_response.split('|')[1]
                else
                  codes << topic_response
                end
                #codes << categorize_survey(topic, :topic)
              end
              question_h[:freq].each do |freq|
                codes << categorize_survey(freq, :freq)
              end
              question_h[:mode].each do |mode|
                mode_response = categorize_survey(mode, :mode)
                if /^F5\|/.match(mode_response)
                  #there is 'other' choice with textbox response. Grab this
                  codes << "F5"
                  other[:modes] << mode_response.split('|')[1]
                else
                  codes << mode_response
                end
              end
              #(0)mbr_id, (1)all checkboxes checked, (2)log_id, (3)other input
              codes_pkg = [logid[0],codes,logid[1],""]
              other.each do |k,v|
                if !v.empty?
                  codes_pkg[3] += "#{k}:#{v}"
                  other[k]=[]
                end
              end
              mbr_codes << codes_pkg
            else
              puts "nothing found"
            end
          end #if jotform regexp
        end #log_ids.each
        #mbr_codes.each do |k,v|
        #  puts "id: #{k}, codes: #{v}"
        #end
        mbr_codes
    end
    def categorize_survey(answer_str, question_symbol)
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
          return_code = "T11|#{answer_str}"
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
          if return_code.nil?
            #this is 'other'
            return_code = "F5|#{answer_str}"
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
  end
end
