class APN::App < APN::Base

  has_many :groups, :class_name => 'APN::Group', :dependent => :destroy
  has_many :devices, :class_name => 'APN::Device', :dependent => :destroy
  has_many :notifications, :through => :devices, :dependent => :destroy
  has_many :unsent_notifications, :through => :devices
  has_many :group_notifications, :through => :groups
  has_many :unsent_group_notifications, :through => :groups

  def cert
    File.read(configatron.apn.cert)
  end

  # Opens a connection to the Apple APN server and attempts to batch deliver
  # an Array of group notifications.
  #
  #
  # As each APN::GroupNotification is sent the <tt>sent_at</tt> column will be timestamped,
  # so as to not be sent again.
  #
  def send_notifications
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    APN::App.send_notifications_for_cert(self.cert, self.id)
  end

  # Enhanced format changes and error handling copied from github.com/greenhat/apn_on_rails.
  def self.response_from_apns(connection)
    timeout = 2
    if IO.select([connection], nil, nil, timeout)
      buf = connection.read(6)
      if buf
        command, error_code, notification_id = buf.unpack('CCN')
        [error_code, notification_id]
      end
    end
  end

  def self.send_notifications
    apps = APN::App.all
    apps.each do |app|
      app.send_notifications
    end
    if !configatron.apn.cert.blank?
      global_cert = File.read(configatron.apn.cert)
      send_notifications_for_cert(global_cert, nil)
    end
  end

  # Enhanced APN format response processing.
  def self.check_for_send_error(the_cert, app_id, conn)
    error_code, notif_id = response_from_apns(conn)
    if error_code
      case error_code
      when 0
        error_text = "No errors encountered"
      when 1
        error_text = "Processing error (problem on Apple's end)"
      when 2
        error_text = "Missing device token"
      when 3
        error_text = "Missing topic (topic = app's bundle identifier)"
      when 4
        error_text = "Missing payload"
      when 5
        error_text = "Invalid token size"
      when 6
        error_text = "Invalid topic size"
      when 7
        error_text = "Invalid payload size"
      when 8
        error_text = "Invalid token"
      when 255
        error_text = "None (unknown)"
      else
        error_text = "Unknown error code (#{error_code})"
      end
      logger.debug "  [1;31mAPN send notificiation error:#{error_code}(#{error_text}), apn_notification.id:#{notif_id}[0m"
      puts "  APN send notification error:#{error_code}(#{error_text}), apn_notification.id:#{notif_id}"
      if error_code == 8
        failed_notification = APN::Notification.find(notif_id)
        unless failed_notification.nil?
          unless failed_notification.device.nil?
            logger.debug "  [1;31mRemoving invalid device: #{failed_notification.device.inspect}[0m"
            puts "  Removing invalid device: #{failed_notification.device.inspect}"
            APN::Device.delete(failed_notification.device.id)
            # retry sending notifications after invalid token was deleted
            send_notifications_for_cert(the_cert, app_id)
          end
        end
      end
    end
  end

  # Enhanced format changes and error handling copied from github.com/greenhat/apn_on_rails.
  def self.send_notifications_for_cert(the_cert, app_id)
    # unless self.unsent_notifications.nil? || self.unsent_notifications.empty?
      if (app_id == nil)
        conditions = "app_id is null"
      else
        conditions = ["app_id = ?", app_id]
      end
      begin
        APN::Connection.open_for_delivery({:cert => the_cert}) do |conn, sock|
          APN::Device.find_each(:conditions => conditions) do |dev|
            dev.unsent_notifications.each do |noty|
              begin
                conn.write(noty.enhanced_message_for_sending)
                noty.sent_at = Time.now
                noty.save
                # Read the APN server's response (if any)
                self.check_for_send_error(the_cert, app_id, conn)
              rescue Exception => e
                logger.debug "[1;31mError '#{e.message}' on APN send notification[0m"
                puts "Error '#{e.message}' on APN send notification"
                if e.message == "Broken pipe"
                  # Write failed (disconnected). Response handling was originally here, but this
                  # rescue clause was not being invoked for any of the error response conditions,
                  # so the response handling code was moved above, outside this clause, which
                  # empirically works.
                end
              end
            end
          end
        end
      rescue Exception => e
        log_connection_exception(e)
      end
    # end
  end

  def send_group_notifications
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    unless self.unsent_group_notifications.nil? || self.unsent_group_notifications.empty?
      #APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock|
      #  unsent_group_notifications.each do |gnoty|
      #    gnoty.devices.find_each do |device|
      #      conn.write(gnoty.message_for_sending(device))
      #    end
      #    gnoty.sent_at = Time.now
      #    gnoty.save
      #  end
      #end
      unsent_group_notifications.each do |gnoty|
        failed = 0
        devices_to_send = gnoty.devices.count
        gnoty.devices.find_in_batches(:batch_size => 100) do |devices|
          APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock|
            devices.each do |device|
              begin
                conn.write(gnoty.message_for_sending(device))
              rescue Exception => e
                puts e.message
                failed += 1
              end
            end
          end
        end
        puts "Sent to: #{devices_to_send - failed}/#{devices_to_send} "
        gnoty.sent_at = Time.now
        gnoty.save
      end
    end
  end

  def send_group_notification(gnoty)
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    unless gnoty.nil?
      APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock|
        gnoty.devices.find_each do |device|
          conn.write(gnoty.message_for_sending(device))
        end
        gnoty.sent_at = Time.now
        gnoty.save
      end
    end
  end

  def self.send_group_notifications
    apps = APN::App.all
    apps.each do |app|
      app.send_group_notifications
    end
  end

  # Retrieves a list of APN::Device instnces from Apple using
  # the <tt>devices</tt> method. It then checks to see if the
  # <tt>last_registered_at</tt> date of each APN::Device is
  # before the date that Apple says the device is no longer
  # accepting notifications then the device is deleted. Otherwise
  # it is assumed that the application has been re-installed
  # and is available for notifications.
  #
  # This can be run from the following Rake task:
  #   $ rake apn:feedback:process
  def process_devices
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    APN::App.process_devices_for_cert(self.cert)
  end # process_devices

  def self.process_devices
    apps = APN::App.all
    apps.each do |app|
      app.process_devices
    end
    if !configatron.apn.cert.blank?
      global_cert = File.read(configatron.apn.cert)
      APN::App.process_devices_for_cert(global_cert)
    end
  end

  def self.process_devices_for_cert(the_cert)
    APN::Feedback.devices(the_cert).each do |device|
      if device.last_registered_at < device.feedback_at
        logger.debug "  [1;31mRemoving uninstalled device: #{device.inspect}[0m"
        puts "  Removing uninstalled device: #{device.inspect}"
        device.destroy
      end
    end
  end

  protected

  def self.log_connection_exception(ex)
    STDERR.puts ex.message
    raise ex
  end

end
