require_relative '../config/sequel'
require_relative 'services/jotform_parser'
require 'did_you_mean'

module MemberTracker
  RecordResult = Struct.new(:success?, :member_id, :message)

  class Member < Sequel::Model
    NAME_SIMILARITY_THRESHOLD = 0.88
    GUEST_PLACEHOLDER_EMAIL = 'GUEST@W7LT.ORG'.freeze

    one_to_one :auth_user, :class=>"MemberTracker::AuthUser", key: :mbr_id
    one_to_many :logs, :class=>"MemberTracker::Log", key: :mbr_id
    many_to_many :units, left_key: :mbr_id, right_key: :unit_id, join_table: :members_units
    many_to_many :events, left_key: :mbr_id, right_key: :event_id, join_table: :members_events
    one_to_many :payments, :class=>"MemberTracker::Payment", key: :mbr_id
    one_to_many :audit_logs, :class=>"MemberTracker::AuditLog", key: :mbr_id
    many_to_one :refer_types, :class=>"MemberTracker::ReferType", key: :refer_type_id
    one_to_many :member_actions, :class=>"MemberTracker::MemberAction", key: :member_target
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
    # Finds members that might be the same real person as `candidate` — used to
    # flag possible duplicates on member create/update, and on event guest
    # registration (both are just rows in `members`; guest vs member is only a
    # mbr_type distinction, not a different identity-matching problem).
    #
    # candidate: hash (string- or symbol-keyed) with any of fname/lname/email/callsign.
    #   Guests may legitimately supply only 2 of these 4 fields (per the event
    #   guest form's own "at least 2 of 4" rule) — every field here is optional
    #   and blank-tolerant; the fuzzy-name check simply doesn't fire if either
    #   name half is missing, falling back to whatever exact signals (email/
    #   callsign) are present.
    # exclude_id: member id to omit from results (the record being edited)
    #
    # Returns a deduped array of Member instances (id/fname/lname/email/callsign
    # only), exact email/callsign matches sorted before fuzzy-name matches.
    def self.find_possible_duplicates(candidate, exclude_id: nil)
      candidate = candidate.transform_keys { |k| k.to_s.to_sym }

      cand_fname    = candidate[:fname].to_s.strip.upcase
      cand_lname    = candidate[:lname].to_s.strip.upcase
      cand_email    = candidate[:email].to_s.strip.upcase
      cand_callsign = candidate[:callsign].to_s.strip.upcase

      return [] if cand_fname.empty? && cand_lname.empty? &&
                   cand_email.empty? && cand_callsign.empty?

      scope = select(:id, :fname, :lname, :email, :callsign)
      scope = scope.exclude(id: exclude_id) if exclude_id

      email_matches    = []
      callsign_matches = []
      name_matches     = []

      scope.all.each do |m|
        m_email    = m.email.to_s.strip.upcase
        m_callsign = m.callsign.to_s.strip.upcase
        m_fname    = m.fname.to_s.strip.upcase
        m_lname    = m.lname.to_s.strip.upcase

        if !cand_email.empty? && cand_email != GUEST_PLACEHOLDER_EMAIL &&
           !m_email.empty? && m_email != GUEST_PLACEHOLDER_EMAIL &&
           cand_email == m_email
          email_matches << m
        end

        if !cand_callsign.empty? && cand_callsign != 'NO CALL' &&
           !m_callsign.empty? && m_callsign != 'NO CALL' &&
           cand_callsign == m_callsign
          callsign_matches << m
        end

        if !cand_fname.empty? && !cand_lname.empty? &&
           !m_fname.empty? && !m_lname.empty?
          fname_score = DidYouMean::JaroWinkler.distance(cand_fname, m_fname)
          lname_score = DidYouMean::JaroWinkler.distance(cand_lname, m_lname)
          if fname_score >= NAME_SIMILARITY_THRESHOLD &&
             lname_score >= NAME_SIMILARITY_THRESHOLD
            name_matches << m
          end
        end
      end

      (email_matches + callsign_matches + name_matches).uniq(&:id)
    end
    def get_jf_data
      JotformParser.call
    end
  end
end
