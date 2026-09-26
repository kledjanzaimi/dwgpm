module ActivityHelper
  # Plain-language labels for audit_logs.action. Unknown actions fall back to
  # a humanized version, so new ones still read sensibly.
  ACTION_LABELS = {
    "upload" => "Uploaded", "download" => "Downloaded", "locate" => "Opened drawing path",
    "mkdir" => "Created folder", "delete" => "Deleted", "reject" => "Blocked path",
    "member_add" => "Added member", "member_remove" => "Removed member",
    "project_create" => "Created project",
    "login" => "Signed in", "logout" => "Signed out",
    "user_create" => "Created user", "user_disable" => "Disabled user", "user_enable" => "Enabled user",
    "template_create" => "Created template", "template_update" => "Changed template",
    "template_delete" => "Deleted template", "template_resync" => "Created missing folders"
  }.freeze

  DENIED_LABELS = { "login" => "Failed sign-in", "upload" => "Upload refused" }.freeze

  def action_label(log)
    return DENIED_LABELS.fetch(log.action, "Denied: #{action_name_for(log.action).downcase}") unless log.allowed?
    action_name_for(log.action)
  end

  def action_name_for(action) = ACTION_LABELS.fetch(action, action.to_s.humanize)

  # Colour family for the badge: destructive, access/admin changes, denied, or routine.
  def action_tone(log)
    return "denied" unless log.allowed?
    case log.action
    when "delete", "member_remove", "user_disable", "template_delete" then "danger"
    when /\A(member_|user_|template_|project_)/ then "admin"
    else "routine"
    end
  end
end
