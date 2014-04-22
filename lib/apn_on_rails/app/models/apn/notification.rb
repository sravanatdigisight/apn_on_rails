# Represents the message you wish to send.
# An APN::Notification belongs to an APN::Device.
#
# Example:
#   apn = APN::Notification.new
#   apn.badge = 5
#   apn.sound = 'my_sound.aiff'
#   apn.alert = 'Hello!'
#   apn.device = APN::Device.find(1)
#   apn.save
#
# To deliver call the following method:
#   APN::Notification.send_notifications
#
# As each APN::Notification is sent the <tt>sent_at</tt> column will be timestamped,
# so as to not be sent again.
class APN::Notification < APN::Base
  include ::ActionView::Helpers::TextHelper
  extend ::ActionView::Helpers::TextHelper
  serialize :custom_properties
  serialize :alert

  belongs_to :device, :class_name => 'APN::Device'
  has_one    :app,    :class_name => 'APN::App', :through => :device

  # Stores the text alert message you want to send to the device.
  #
  # If the message is over 150 characters long it will get truncated
  # to 150 characters with a <tt>...</tt>
  def alert=(message)
    if !message.blank? && message.size > 145
      message = truncate(message, :length => 145)
    end
    write_attribute('alert', message)
  end

  # Creates a Hash that will be the payload of an APN.
  #
  # Example:
  #   apn = APN::Notification.new
  #   apn.badge = 5
  #   apn.sound = 'my_sound.aiff'
  #   apn.alert = 'Hello!'
  #   apn.apple_hash # => {"aps" => {"badge" => 5, "sound" => "my_sound.aiff", "alert" => "Hello!"}}
  #
  # Example 2:
  #   apn = APN::Notification.new
  #   apn.badge = 0
  #   apn.sound = true
  #   apn.custom_properties = {"typ" => 1}
  #   apn.apple_hash # => {"aps" => {"badge" => 0, "sound" => "1.aiff"}, "typ" => "1"}
  #
  # Example 3:
  #   apn = APN::Notification.new
  #   apn.badge = 0
  #   apn.sound = true
  #   apn.custom_properties = {"typ" => 1}
  #   apn.apple_hash # => {"aps" => {"badge" => 0, "sound" => "1.aiff", "alert" => {"body" => "test", "action-loc-key" => "test-loc-key"}}, "typ" => "1"}

  def apple_hash
    result = {}
    result['aps'] = {}
    if self.alert
      if self.alert.kind_of?(Hash)
        result['aps']['alert'] = {}
        self.alert.each do |key,value|
          result['aps']['alert']["#{key}"] = "#{value}"
        end
      else
        result['aps']['alert'] = self.alert
      end
    end
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
  # Unmodified apn_on_rails 0.5.1 implements only this "simple notification format".
  def message_for_sending
    command = ['0'].pack('H')
    token = self.device.to_hexa
    token_length = [token.bytesize].pack('n')
    payload = self.to_apple_json
    payload_length = [payload.bytesize].pack('n')
    message = command + token_length + token + payload_length + payload
    raise APN::Errors::ExceededMessageSizeError.new(message) if payload.bytesize > 256
    message
  end

  # Enhanced format changes copied from github.com/greenhat/apn_on_rails.
  # Creates the enhanced binary message needed to send to Apple in order to have the ability to
  # retrieve error description from Apple server in case of connection was cancelled.
  # Default expiry time is 1 day.
  def enhanced_message_for_sending (seconds_to_expire = configatron.apn.notification_expiration_seconds)
    command = ['1'].pack('H')
    notification_id = [self.id].pack('N')
    #expiry = "#{(Time.now + 1.day).to_i.pack('N')}"
    expiry = [Time.now.to_i + seconds_to_expire].pack('N')
    #devoce = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA'
    #token = devoce.to_hexa
    token = self.device.to_hexa
    token_length = [token.bytesize].pack('n')
    payload = self.to_apple_json
    payload_length = [payload.bytesize].pack('n')
    message = command + notification_id + expiry + token_length + token + payload_length + payload
    puts "[1;31mMESSAGE=#{message}[0m"
    puts "[1;31mMESSAGE=#{message.unpack('H*')}[0m"
    File.open('/tmp/DOUG1.dat', 'wb') {|file| file.write(message)}
    raise APN::Errors::ExceededMessageSizeError.new(message) if message.size.to_i > 256
    message
  end

  def self.send_notifications
    ActiveSupport::Deprecation.warn("The method APN::Notification.send_notifications is deprecated.  Use APN::App.send_notifications instead.")
    APN::App.send_notifications
  end

end # APN::Notification
