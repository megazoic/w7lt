require_relative '../config/sequel'

module MemberTracker
  class Action < Sequel::Model
    one_to_many :logs, :class=>Log, key: :action_id
  end
end
