module Providers
  class Authentication < ApplicationRecord
    include NewWithTypeStiMixin
    def self.new(*args, &block)
      if self == Authentication
        AuthUseridPassword.new(*args, &block)
      else
        super
      end
    end

    belongs_to :resource, :polymorphic => true

    before_save :set_credentials_changed_on
    after_save :after_authentication_changed

    serialize :options

    # TODO: DELETE ME!!!!
    ERRORS = {
      :incomplete => "Incomplete credentials",
      :invalid    => "Invalid credentials",
    }.freeze

    STATUS_SEVERITY = Hash.new(-1).merge(
      ""            => -1,
      "valid"       => 0,
      "none"        => 1,
      "incomplete"  => 1,
      "error"       => 2,
      "unreachable" => 2,
      "invalid"     => 3,
    ).freeze

    RETRYABLE_STATUS = %w(error unreachable).freeze

    CREDENTIAL_TYPES = {
      :external_credential_types         => 'ManageIQ::Providers::ExternalAutomationManager::Authentication',
      :embedded_ansible_credential_types => 'ManageIQ::Providers::EmbeddedAutomationManager::Authentication'
    }.freeze

    def status_severity
      STATUS_SEVERITY[status.to_s.downcase]
    end

    def retryable_status?
      RETRYABLE_STATUS.include?(status.to_s.downcase)
    end

    def authentication_type
      authtype.nil? ? :default : authtype.to_sym
    end

    def available?
      password.present? || auth_key.present?
    end

    # The various status types:
    #   valid, invalid
    #   incomplete  (???)
    #   unreachable (for all communications errors)
    #   error (for unpredictable errors)
    def validation_successful
      new_status = :valid
      #_log.info("[#{resource_type}] [#{resource_id}], previously valid/invalid on: [#{last_valid_on}]/[#{last_invalid_on}], previous status: [#{status}]") if status != new_status.to_s
      update_attributes(:status => new_status.to_s.capitalize, :status_details => 'Ok', :last_valid_on => Time.now.utc)
      #raise_event(new_status)
    end

    def validation_failed(status = :unreachable, message = nil)
      message ||= ERRORS[status]
      #_log.warn("[#{resource_type}] [#{resource_id}], previously valid on: #{last_valid_on}, previous status: [#{self.status}]")
      update_attributes(:status => status.to_s.capitalize, :status_details => message.to_s.truncate(200), :last_invalid_on => Time.now.utc)
      #raise_event(status, message)
    end

    def assign_values(options)
      self.attributes = options
    end

    def self.build_credential_options
      CREDENTIAL_TYPES.each_with_object({}) do |(k, v), hash|
        hash[k] = v.constantize.descendants.each_with_object({}) do |klass, fields|
          fields[klass.name] = klass::API_OPTIONS if defined? klass::API_OPTIONS
        end
      end
    end

    private

    def set_credentials_changed_on
      return unless @auth_changed
      self.credentials_changed_on = Time.now.utc
    end

    def after_authentication_changed
      return unless @auth_changed
      #_log.info("[#{resource_type}] [#{resource_id}], previously valid on: [#{last_valid_on}]")

      #raise_event(:changed)

      # Async validate the credentials
      # resource.authentication_check_types_queue(authentication_type) if resource
      @auth_changed = false
    end
  end
end