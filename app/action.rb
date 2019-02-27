require_relative '../config/sequel'

module MemberTracker
  class Action < Sequel::Model
    many_to_many :logs, left_key: :action_id, right_key: :log_id, join_table: :logs_actions
  end
end
