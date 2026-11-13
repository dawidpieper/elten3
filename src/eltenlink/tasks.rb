# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

module EltenLink
  class TaskProject
    attr_accessor :id, :author, :name, :creation, :personal

    def initialize(id: 0, author: nil, name: "", creation: nil, personal: false)
      @id = id.to_i
      @author = author.to_s
      @name = name.to_s
      @creation = creation.is_a?(Time) ? creation : Time.at(creation.nil? ? 0 : creation.to_i)
      @personal = personal == true || @id == 0
    end

    def personal?
      @personal == true || @id == 0
    end

    def owned_by?(user)
      !personal? && @author.to_s.casecmp(user.to_s) == 0
    end
  end

  class Task
    attr_accessor :id, :project_id, :creator, :name, :description, :creationtime,
                  :plantime, :completed, :completiontime, :performer, :parent,
                  :children_count, :children, :frequency

    def initialize(id: 0, project_id: 0, creator: nil, name: "", description: "",
                   creationtime: nil, plantime: nil, completed: false,
                   completiontime: nil, performer: nil, parent: 0,
                   children_count: 0, children: [], frequency: 0)
      @id = id.to_i
      @project_id = project_id.to_i
      @creator = creator.to_s
      @name = name.to_s
      @description = description.to_s
      @creationtime = time_value(creationtime)
      @plantime = optional_time_value(plantime)
      @completed = completed == true
      @completiontime = optional_time_value(completiontime)
      @performer = performer.nil? || performer.to_s.empty? ? nil : performer.to_s
      @parent = parent.to_i
      @children_count = children_count.to_i
      @children = children.to_a
      @frequency = frequency.to_i
      @frequency = 0 if @frequency < -1
    end

    def completed?
      @completed == true
    end

    def due?
      @plantime != nil
    end

    def overdue?(now=Time.now)
      !completed? && due? && @plantime.to_i < now.to_i
    end

    def recurring?
      @frequency != 0
    end

    def composite?
      @children_count.positive? || !@children.empty?
    end

    private

    def time_value(value)
      value.is_a?(Time) ? value : Time.at(value.nil? ? 0 : value.to_i)
    end

    def optional_time_value(value)
      return nil if value.nil?

      number = value.respond_to?(:to_time) ? value.to_time.to_i : value.to_i
      number.positive? ? Time.at(number) : nil
    end
  end

  class TaskProjectShare
    attr_accessor :id, :project_id, :user, :accepted

    def initialize(id: 0, project_id: 0, user: "", accepted: false)
      @id = id.to_i
      @project_id = project_id.to_i
      @user = user.to_s
      @accepted = accepted == true
    end
  end

  class TaskProjectInvitation
    attr_accessor :id, :project, :user, :accepted

    def initialize(id: 0, project: nil, user: "", accepted: false)
      @id = id.to_i
      @project = project
      @user = user.to_s
      @accepted = accepted == true
    end
  end

  module Tasks
    class << self
      def reminder_settings(client, project=nil)
        path = project == nil ? "/api/v1/tasks/reminders" : "/api/v1/tasks/projects/#{project_id(project)}/reminders"
        client.api_data("GET", path)
      end

      def update_reminder_settings(client, values, project=nil)
        path = project == nil ? "/api/v1/tasks/reminders" : "/api/v1/tasks/projects/#{project_id(project)}/reminders"
        client.api_data("PATCH", path, values)
      end

      def projects(client)
        data = client.api_data("GET", "/api/v1/tasks/projects")
        data["projects"].to_a.map { |row| project_from(row) }
      end

      def invitations(client)
        data = client.api_data("GET", "/api/v1/tasks/projects/invitations")
        data["invitations"].to_a.map do |row|
          TaskProjectInvitation.new(
            id: row["id"],
            project: project_from(row["project"] || {}),
            user: row["user"],
            accepted: truthy?(row["accepted"])
          )
        end
      end

      def participants(client)
        data = client.api_data("GET", "/api/v1/tasks/projects/participants")
        data["projects"].to_a.each_with_object({}) do |row, projects|
          projects[row["project"].to_i] = row["users"].to_a.map(&:to_s)
        end
      end

      def create_project(client, name:)
        data = client.api_data("POST", "/api/v1/tasks/projects", { "name" => name })
        data["id"].to_i
      end

      def update_project(client, project, name:)
        client.api_data(
          "PATCH",
          "/api/v1/tasks/projects/#{project_id(project)}",
          { "name" => name }
        )
        true
      end

      def delete_project(client, project)
        client.api_data("DELETE", "/api/v1/tasks/projects/#{project_id(project)}")
        true
      end

      def shares(client, project)
        data = client.api_data("GET", "/api/v1/tasks/projects/#{project_id(project)}/shares")
        data["shares"].to_a.map do |row|
          TaskProjectShare.new(
            id: row["id"],
            project_id: row["project"],
            user: row["user"],
            accepted: truthy?(row["accepted"])
          )
        end
      end

      def add_share(client, project, user)
        client.api_data(
          "POST",
          "/api/v1/tasks/projects/#{project_id(project)}/shares",
          { "user" => user }
        )
      end

      def accept_share(client, project)
        client.api_data("PATCH", "/api/v1/tasks/projects/#{project_id(project)}/shares/membership")
        true
      end

      def delete_membership(client, project)
        client.api_data("DELETE", "/api/v1/tasks/projects/#{project_id(project)}/shares/membership")
        true
      end

      def delete_share(client, project, user)
        client.api_data(
          "DELETE",
          "/api/v1/tasks/projects/#{project_id(project)}/shares/#{user.to_s.urlenc}"
        )
        true
      end

      def list(client, project: nil, parent: 0, status: :pending, performer: nil)
        params = { "parent" => parent.to_i, "status" => status.to_s }
        params["project"] = project_id(project) unless project.nil?
        params["performer"] = performer.to_s unless performer.nil? || performer.to_s.empty?
        data = client.api_data("GET", "/api/v1/tasks", params)
        data["tasks"].to_a.map { |row| task_from(row) }
      end

      def details(client, task)
        data = client.api_data("GET", "/api/v1/tasks/#{task_id(task)}")
        task_from(data)
      end

      def create(client, project:, name:, description: "", plantime: nil, performer: nil, parent: 0, frequency: 0)
        data = client.api_data(
          "POST",
          "/api/v1/tasks",
          {
            "project" => project_id(project),
            "name" => name,
            "description" => description,
            "plantime" => time_to_i(plantime),
            "performer" => performer,
            "parent" => task_id(parent),
            "frequency" => frequency.to_i
          }
        )
        data["id"].to_i
      end

      def update(client, task, project:, name:, description:, plantime:, performer:, parent:, frequency: 0)
        client.api_data(
          "PATCH",
          "/api/v1/tasks/#{task_id(task)}",
          {
            "project" => project_id(project),
            "name" => name,
            "description" => description,
            "plantime" => time_to_i(plantime),
            "performer" => performer,
            "parent" => task_id(parent),
            "frequency" => frequency.to_i
          }
        )
        true
      end

      def delete(client, task)
        client.api_data("DELETE", "/api/v1/tasks/#{task_id(task)}")
        true
      end

      def complete(client, task)
        client.api_data("PATCH", "/api/v1/tasks/#{task_id(task)}/completion")
        true
      end

      def reopen(client, task)
        client.api_data("DELETE", "/api/v1/tasks/#{task_id(task)}/completion")
        true
      end

      private

      def project_from(row)
        TaskProject.new(
          id: row["id"],
          author: row["author"],
          name: row["name"],
          creation: row["creation"],
          personal: truthy?(row["personal"])
        )
      end

      def task_from(row)
        children = row["children"].to_a.map { |child| task_from(child) }
        Task.new(
          id: row["id"],
          project_id: row["project"],
          creator: row["creator"],
          name: row["name"],
          description: row["description"],
          creationtime: row["creationtime"],
          plantime: row["plantime"],
          completed: truthy?(row["completed"]),
          completiontime: row["completiontime"],
          performer: row["performer"],
          parent: row["parent"],
          children_count: row["children_count"] || children.length,
          children: children,
          frequency: row["frequency"]
        )
      end

      def project_id(project)
        project.respond_to?(:id) ? project.id.to_i : project.to_i
      end

      def task_id(task)
        task.respond_to?(:id) ? task.id.to_i : task.to_i
      end

      def time_to_i(value)
        return 0 if value.nil?
        value.respond_to?(:to_time) ? value.to_time.to_i : value.to_i
      end

      def truthy?(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end
    end
  end
end
