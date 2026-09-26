# Local accounts. When LDAP arrives it replaces the credential check here;
# authorization still comes from memberships (see CLAUDE.md).
class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to login_path, alert: "Too many attempts. Try again in a few minutes." }

  def new
    redirect_to root_path if current_user
  end

  def create
    user = User.authenticate_by(email: params[:email].to_s, password: params[:password].to_s)

    if user&.active?
      reset_session
      session[:user_id] = user.id
      audit!(project: nil, action: "login", path: "")
      redirect_to root_path
    else
      audit!(project: nil, action: "login", path: "", detail: params[:email].to_s.first(255), allowed: false)
      flash.now[:alert] = "Wrong email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    audit!(project: nil, action: "logout", path: "")
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
