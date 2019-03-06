require_relative '../config/sequel'

module MemberTracker
  class Member < Sequel::Model
    one_to_one :auth_user, :class=>"MemberTracker::Auth_user", key: :a_user_id
    one_to_many :logs, :class=>"MemberTracker::Log", key: :mbr_id
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
  end
end