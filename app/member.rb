module MemberTracker
  require_relative '../config/sequel'
  RecordResult = Struct.new(:success?, :member_id, :error_message)
  class Member
    def record(member)
      unless member.key?('lname')
        message = 'Invalid member: \'lname\' is required'
        return RecordResult.new(false, nil, message)
      end
      DB[:members].insert(member)
      id = DB[:members].max(:id)
      RecordResult.new(true, id, nil)
    end
    def members_with_lastname(name)
      DB[:members].where(lname: name).all
    end
  end
end