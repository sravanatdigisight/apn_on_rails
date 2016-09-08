class APN::GroupNotification < APN::Base
  include ::ActionView::Helpers::TextHelper
  extend ::ActionView::Helpers::TextHelper
  serialize :custom_properties

  belongs_to :group, :class_name => 'APN::Group'
  has_one    :app, :class_name => 'APN::App', :through => :group
  has_many   :device_groupings, :through => :group

  validates_presence_of :group_id

  def devices
    self.group.devices
  end

  # Stores the text alert message you want to send to the device.
  #
  # If the message is over 150 characters long it will get truncated
  # to 150 characters with a <tt>...</tt>
  def alert=(message)
    if !message.blank? && message.size > 150
      message = truncate(message, :length => 150)
    end
    write_attribute('alert', message)
  end

  # Creates a Hash that will be the payload of an APN.
  #
  # Example:
  #   apn = APN::GroupNotification.new
  #   apn.badge = 5
  #   apn.sound = 'my_sound.aiff'
  #   apn.alert = 'Hello!'
  #   apn.apple_hash # => {"aps" => {"badge" => 5, "sound" => "my_sound.aiff", "alert" => "Hello!"}}
  #
  # Example 2:
  #   apn = APN::GroupNotification.new
  #   apn.badge = 0
  #   apn.sound = true
  #   apn.custom_properties = {"typ" => 1}
  #   apn.apple_hash # => {"aps" => {"badge" => 0, "sound" => 1.aiff},"typ" => "1"}
  def apple_hash
    result = {}
    result['aps'] = {}
    result['aps']['alert'] = self.alert if self.alert
    result['aps']['badge'] = self.badge.to_i if self.badge
    if self.sound
      result['aps']['sound'] = self.sound if self.sound.is_a? String
      result['aps']['sound'] = "1.aiff" if self.sound.is_a?(TrueClass)
    end
    if self.custom_properties
      self.custom_properties.each do |key,value|
        result["#{key}"] = "#{value}"
      end
    end
    result
  end

  # Creates the JSON string required for an APN message.
  #
  # Example:
  #   apn = APN::Notification.new
  #   apn.badge = 5
  #   apn.sound = 'my_sound.aiff'
  #   apn.alert = 'Hello!'
  #   apn.to_apple_json # => '{"aps":{"badge":5,"sound":"my_sound.aiff","alert":"Hello!"}}'
  def to_apple_json
    self.apple_hash.to_json
  end

  # Creates the binary message needed to send to Apple.
  def message_for_sending(device)
    command = ['0'].pack('H') # Now, APN_ON_RAILS implements only "simple notification format".
    token = device.to_hexa
    token_length = [token.bytesize].pack('n')
    payload = self.to_apple_json
    payload_length = [payload.bytesize].pack('n')
    message = command + token_length + token + payload_length + payload
    raise APN::Errors::ExceededMessageSizeError.new(message) if payload.bytesize > 1900
    message
  end

end # APN::Notification
