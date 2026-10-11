module Vernacular
  # The per-checkpoint self-improvement step. After a checkpoint passes, a
  # fresh read-only reviewer looks at what its gates caught and turns each
  # mechanically detectable finding into a check the build gate runs from
  # then on. Everything it cannot encode as a check becomes a proposal in
  # vernacular/improvements.md for a human; it never edits prompts or code.
  class Improvement
    SCHEMA = {
      type: 'object', required: %w[checks proposals],
      properties: {
        checks: {
          type: 'array',
          items: {
            type: 'object', required: %w[name why paths pattern message],
            properties: { name: { type: 'string' }, why: { type: 'string' }, paths: { type: 'array', items: { type: 'string' } },
                          pattern: { type: 'string' }, message: { type: 'string' } }
          }
        },
        proposals: {
          type: 'array',
          items: {
            type: 'object', required: %w[title problem mechanism],
            properties: { title: { type: 'string' }, problem: { type: 'string' }, mechanism: { type: 'string' } }
          }
        }
      }
    }.freeze

    def initialize(plan, checkpoint, evidence)
      @plan = plan
      @checkpoint = checkpoint
      @evidence = evidence
    end

    def apply
      return if @evidence.findings.empty?

      existing = Checks.committed
      reply = Claude.review(Prompts.improve(@plan.screen, @checkpoint, @evidence, existing), schema: SCHEMA)
      @evidence.cost(reply.cost)
      return Vernacular.log("#{tag}   improver errored; skipped") unless reply.structured

      added = add_checks(reply.structured['checks'], existing.map(&:name))
      propose(reply.structured['proposals'])
      @evidence.save('improvement.json', reply.structured.merge('accepted_checks' => added))
      Vernacular.log("#{tag}   improver: #{added.size} check(s) added, #{reply.structured['proposals'].size} proposal(s)")
    end

    private

    def tag = "#{@plan.screen}/#{@checkpoint.id}"

    def add_checks(candidates, names)
      candidates.filter_map do |data|
        check = Checks.parse(data)
        problem = Checks.problem(check, names)
        if problem
          Vernacular.log("#{tag}   improver check #{check.name} rejected: #{problem}")
          next
        end

        Checks.write(check)
        names << check.name
        check.name
      end
    end

    def propose(proposals)
      proposals.each do |proposal|
        Ledger.improvements.append("#{proposal['title']} (#{tag})", "#{proposal['problem']}\n\n**Mechanism:** #{proposal['mechanism']}")
      end
    end
  end
end
