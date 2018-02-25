require_relative '../config/sequel'

module MemberTracker
  RecordResult = Struct.new(:success?, :member_id, :error_message)
  class Member < Sequel::Model
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
      data_out = []
      matching_members.each {|m| data_out << m.values}
      data_out
      #DB[:members].where(lname: name).all
    end
  end
end