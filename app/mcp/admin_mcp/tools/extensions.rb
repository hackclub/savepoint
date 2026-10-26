module AdminMcp::Tools::Extensions
  # The Extensions page: who's asked for more time to ship, waiting first.
  class ListExtensions < AdminMcp::Tool
    reads "list_extensions", "List extension requests",
          "Everyone who's asked for more time to ship, and why: waiting first, oldest at the top, then decided. Answers { total, extensions }.",
          { status: { type: "string", enum: %w[pending decided all], description: "Default pending." }, **AdminMcp::Tool::PAGE }

    def self.run(args, _caller)
      status = args[:status] || "pending"
      extensions = Extension.includes(:decided_by, project: :user)
      extensions = case status
      when "pending" then extensions.pending.order(:created_at, :id)
      when "decided" then extensions.decided.order(decided_at: :desc, id: :desc)
      else extensions.order(Arel.sql("status = 'pending' desc"), :created_at, :id)
      end
      total, rows = page(extensions, args)
      { total:, extensions: rows.map { AdminMcp::Present.extension(it) } }
    end
  end

  class DecideExtension < AdminMcp::Tool
    writes "decide_extension", "Approve or deny an extension",
           "Decides a waiting extension request, once (the Extensions page's Approve and Deny buttons). The bot DMs the participant either way. " \
           "Answers { decided }: false when it was decided already.",
           { extension_id: { type: "integer", description: "The extension ID, from list_extensions." },
             decision: { type: "string", enum: Extension::DECISIONS, description: "approved or denied." } },
           required: %w[extension_id decision]

    def self.run(args, caller)
      extension = Extension.find(args[:extension_id])
      decided = extension.decide!(args[:decision], by: caller.user)
      { decided:, message: ("That one's been decided already." unless decided), extension: AdminMcp::Present.extension(extension.reload) }
    end
  end
end
