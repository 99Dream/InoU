import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart';

import 'inou_agent_hooks.dart';

export 'tutor_agent_service.dart';

/// Constructs a `StatefulAgent` configured for InoU's mascot tutor ("诺诺老师").
class InouTutorAgentBuilder {
  const InouTutorAgentBuilder();

  StatefulAgent build({
    required LLMClient client,
    required ModelConfig modelConfig,
    required AgentState state,
    required List<String> systemPrompts,
    required List<Tool> tools,
    HintLevel Function()? hintLevelProvider,
    List<Skill>? skills,
    List<SubAgent>? subAgents,
    ContextCompressor? compressor,
    AgentController? controller,
    FutureOr<void> Function(AgentState state)? autoSaveStateFunc,
    List<AgentHook> extraHooks = const [],
    int maxTurns = 12,
  }) {
    final hooks = <AgentHook>[
      if (hintLevelProvider != null)
        AntiSpoilerHook(hintLevelProvider: hintLevelProvider),
      ...extraHooks,
    ];

    return StatefulAgent(
      name: 'nuonuo_tutor',
      client: client,
      modelConfig: modelConfig,
      state: state,
      systemPrompts: systemPrompts,
      tools: tools,
      skills: skills,
      subAgents: subAgents,
      compressor: compressor,
      controller: controller,
      autoSaveStateFunc: autoSaveStateFunc,
      hooks: hooks,
      // Mascot tutor uses a pedagogical persona rather than terse coding rules.
      withGeneralPrinciples: false,
      maxTurns: maxTurns,
    );
  }
}
