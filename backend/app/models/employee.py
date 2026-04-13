# Employee model has been merged into User (app/models/user.py).
# This file is kept temporarily to avoid import errors in routers that haven't been updated yet.
from app.models.user import User, UserRole, UserStatus

# Aliases for backward compatibility during router migration
Employee = User
EmployeeStatus = UserStatus
