module MemberTracker
  #used to package up status info
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
    end
  end
end