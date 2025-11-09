<script setup>
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import AIConfigModal from './AIConfigModal.vue';
import ContactAPI from '../../../../api/contacts';
import ConversationAPI from '../../../../api/conversations';
import KanbanAPI from '../../../../api/kanban';
import FunnelAPI from '../../../../api/funnel';
import store from '../../../../store';
import Modal from '../../../../components/Modal.vue';

const router = useRouter();
const { t } = useI18n();
const accountId = router.currentRoute.value.params.accountId;
const messages = ref([
  {
    type: 'ai',
    content: t('KANBAN.AI.WELCOME_MESSAGE'),
  },
]);
const inputMessage = ref('');
const isLoading = ref(false);
const showConfigModal = ref(false);
const messagesContainer = ref(null);
const openAIConfig = ref(null);
const isProcessingItems = ref(false);
const selectedSource = ref(null);
const showSourceSelector = ref(false);
const showFunnelSelector = ref(false);
const selectedFunnel = ref(null);
const funnels = ref([]);
const selectedStage = ref(null);
const showConfirmationModal = ref(false);
const selectedSuggestion = ref(null);
const pendingChanges = ref(null);
const isQuickActionsCollapsed = ref(true);

// Carrega a configuração do OpenAI
const loadOpenAIConfig = async () => {
  try {
    const response = await window.axios.get(
      `/api/v1/accounts/${accountId}/integrations/apps`
    );

    const openaiIntegration = response.data?.payload?.find(
      integration => integration.id === 'openai'
    );

    if (openaiIntegration?.enabled && openaiIntegration?.hooks?.[0]?.settings) {
      openAIConfig.value = openaiIntegration.hooks[0].settings;
      return true;
    }
    return false;
  } catch (error) {
    console.error('Erro ao carregar configuração OpenAI:', error);
    return false;
  }
};

// Função para buscar funis
const fetchFunnels = async () => {
  try {
    const { data } = await FunnelAPI.get();
    funnels.value = data;
  } catch (error) {
    console.error('Erro ao carregar funis:', error);
    messages.value.push({
      type: 'ai',
      content: 'Desculpe, ocorreu um erro ao carregar os funis.',
    });
  }
};

// Função auxiliar para obter o primeiro estágio do funil
const getFirstStage = funnel => {
  // Converte o objeto stages em um array de [key, value]
  const stagesArray = Object.entries(funnel.stages);

  // Ordena pelo position e pega o primeiro
  const firstStage = stagesArray.sort(
    (a, b) => a[1].position - b[1].position
  )[0];

  // Retorna a chave do estágio (ex: 'lead', 'new', 'detec_o')
  return firstStage[0];
};

// Função para buscar mensagens de uma conversa
const fetchConversationMessages = async conversationId => {
  try {
    const response = await window.axios.get(
      `/api/v1/accounts/${accountId}/conversations/${conversationId}/messages?before=100`
    );
    return response.data;
  } catch (error) {
    console.error('Erro ao buscar mensagens:', error);
    return null;
  }
};

// Função para processar a criação de itens a partir de contatos
const createItemsFromContacts = async contacts => {
  const firstStage = getFirstStage(selectedFunnel.value);

  try {
    const items = await Promise.all(
      contacts.slice(0, 10).map(async (contact, index) => {
        // Cria um título apenas com o nome do contato
        const title = contact.name || 'Novo Contato';

        // Gera apenas a descrição usando a IA
        const response = await fetch(
          'https://api.openai.com/v1/chat/completions',
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${openAIConfig.value.api_key}`,
            },
            body: JSON.stringify({
              model: 'gpt-4o-mini',
              messages: [
                {
                  role: 'system',
                  content:
                    'Você é um assistente que gera descrições concisas para leads em um funil de vendas. Gere apenas uma descrição curta sem formatação.',
                },
                {
                  role: 'user',
                  content: `Gere uma descrição curta para um lead com os seguintes dados:
                  Nome: ${contact.name}
                  Email: ${contact.email || 'Não informado'}
                  Telefone: ${contact.phone_number || 'Não informado'}`,
                },
              ],
              temperature: 0.7,
            }),
          }
        );

        const aiData = await response.json();
        const description = aiData.choices[0].message.content.trim();

        return {
          funnel_id: selectedFunnel.value.id,
          funnel_stage: firstStage,
          position: index,
          item_details: {
            title,
            description:
              description ||
              `Contato via ${contact.email ? 'email' : 'telefone'}`,
            value: null,
            priority: 'medium',
            email: contact.email,
            phone: contact.phone_number,
            contact_id: contact.id,
            custom_attributes: {},
          },
        };
      })
    );

    for (const item of items) {
      await KanbanAPI.createItem(item);
    }

    return items.length;
  } catch (error) {
    console.error('Erro ao criar itens:', error);
    throw error;
  }
};

// Modifica a função createItemsFromConversations
const createItemsFromConversations = async conversations => {
  if (!conversations || conversations.length === 0) {
    console.log('Nenhuma conversa encontrada');
    return 0;
  }

  const firstStage = getFirstStage(selectedFunnel.value);

  try {
    const items = await Promise.all(
      conversations.slice(0, 10).map(async (conversation, index) => {
        if (!conversation?.meta?.sender) {
          console.log('Conversa sem dados necessários:', conversation);
          return null;
        }

        // Busca todas as mensagens da conversa
        const messagesData = await fetchConversationMessages(conversation.id);
        if (!messagesData) return null;

        // Prepara os dados da conversa para análise
        const conversationData = {
          contact: conversation.meta.sender,
          messages: messagesData.payload
            .filter(msg => msg.content_type === 'text')
            .map(msg => ({
              content: msg.content,
              sender_type: msg.sender?.type || 'system',
              created_at: new Date(msg.created_at * 1000).toLocaleDateString(),
            })),
          status: conversation.status,
          priority: conversation.priority,
          assignee: conversation.meta.assignee,
          channel: conversation.meta.channel,
          created_at: new Date(
            conversation.created_at * 1000
          ).toLocaleDateString(),
          last_activity: new Date(
            conversation.last_activity_at * 1000
          ).toLocaleDateString(),
        };

        // Gera análise usando a IA
        const response = await fetch(
          'https://api.openai.com/v1/chat/completions',
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${openAIConfig.value.api_key}`,
            },
            body: JSON.stringify({
              model: 'gpt-4o-mini',
              messages: [
                {
                  role: 'system',
                  content:
                    'Você é um assistente que analisa conversas de vendas e suporte. Retorne APENAS um objeto JSON válido (sem formatação markdown ou código) com os campos: title (string), description (string), value (number ou null - extraia qualquer valor monetário mencionado em reais), priority (string: low, medium, high, urgent), scheduling_type (string: deadline ou scheduled), scheduled_at (data ISO ou null), deadline_at (data ISO ou null), offers (array de objetos com value e description). Se houver menção a valores em reais, crie uma oferta com esse valor. Se houver múltiplos valores mencionados, crie múltiplas ofertas.',
                },
                {
                  role: 'user',
                  content: `Analise esta conversa e extraia as informações relevantes, prestando especial atenção a valores monetários e prazos mencionados:
                  Cliente: ${conversationData.contact.name}
                  Email: ${conversationData.contact.email}
                  Telefone: ${conversationData.contact.phone_number}
                  Canal: ${conversationData.channel}
                  Status: ${conversationData.status}
                  Mensagens:
                  ${conversationData.messages
                    .map(
                      msg =>
                        `[${msg.sender_type}] ${msg.created_at}: ${msg.content}`
                    )
                    .join('\n')}
                  Prioridade: ${conversationData.priority || 'normal'}
                  Atendente: ${conversationData.assignee?.name}`,
                },
              ],
              temperature: 0.7,
            }),
          }
        );

        const aiData = await response.json();
        let analysis;

        try {
          // Remove qualquer formatação markdown ou código que a IA possa ter adicionado
          const cleanJson = aiData.choices[0].message.content
            .replace(/```json\n?/g, '')
            .replace(/```\n?/g, '')
            .trim();

          analysis = JSON.parse(cleanJson);
        } catch (parseError) {
          console.error('Erro ao parsear JSON da IA:', parseError);
          // Usa valores padrão em caso de erro
          analysis = {
            title: `Conversa com ${conversation.meta.sender.name}`,
            description:
              conversationData.messages[conversationData.messages.length - 1]
                .content || 'Nova conversa',
            value: null,
            priority: conversation.priority || 'medium',
            scheduling_type: 'deadline',
            scheduled_at: null,
            deadline_at: null,
            offers: [],
          };
        }

        // Retorna o item formatado com os dados da IA
        return {
          funnel_id: selectedFunnel.value.id,
          funnel_stage: firstStage,
          position: index,
          item_details: {
            title: analysis.title,
            description: analysis.description,
            value: analysis.value,
            priority: analysis.priority || conversation.priority || 'medium',
            conversation_id: conversation.id,
            agent_id: conversation.meta.assignee?.id,
            contact_id: conversation.meta.sender.id,
            channel: conversation.meta.channel,
            status: conversation.status,
            scheduling_type: analysis.scheduling_type || 'deadline',
            scheduled_at: analysis.scheduled_at,
            deadline_at: analysis.deadline_at,
            offers: analysis.offers || [],
            currency:
              analysis.value || (analysis.offers && analysis.offers.length > 0)
                ? {
                    code: 'BRL',
                    locale: 'pt-BR',
                    symbol: 'R$',
                  }
                : null,
            custom_attributes: {},
          },
        };
      })
    );

    const validItems = items.filter(item => item !== null);

    for (const item of validItems) {
      await KanbanAPI.createItem(item);
    }

    return validItems.length;
  } catch (error) {
    console.error('Erro ao criar itens:', error);
    throw error;
  }
};

// Modifica a função sendMessage para processar a criação de itens
const sendMessage = async () => {
  if (!inputMessage.value.trim() || isLoading.value) return;

  // Send telemetry for message sent
  await sendTelemetryEvent('message_sent', { message: inputMessage.value });

  // Verifica configuração OpenAI...
  if (!openAIConfig.value) {
    const hasConfig = await loadOpenAIConfig();
    if (!hasConfig) {
      showConfigModal.value = true;
      return;
    }
  }

  const userMessage = inputMessage.value;
  inputMessage.value = '';
  isLoading.value = true;

  messages.value.push({
    type: 'user',
    content: userMessage,
  });

  try {
    // Se a mensagem contém pedido para gerar itens
    if (
      userMessage.toLowerCase().includes('gerar') ||
      userMessage.toLowerCase().includes('criar')
    ) {
      await fetchFunnels();
      if (funnels.value.length === 0) {
        messages.value.push({
          type: 'ai',
          content:
            'Nenhum funil encontrado. Por favor, crie um funil primeiro.',
        });
        return;
      }
      showFunnelSelector.value = true;
      messages.value.push({
        type: 'ai',
        content: 'Primeiro, selecione o funil onde deseja criar os itens:',
      });
      isLoading.value = false;
      return;
    }

    // Para outras mensagens, usa a API do OpenAI
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${openAIConfig.value.api_key}`,
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `Você é um assistente especializado em metodologia Kanban e gestão ágil de projetos. 
                     Para criar itens no quadro, o usuário deve usar as palavras "gerar" ou "criar".
                     Exemplo: "Gerar itens para o quadro" ou "Criar itens no kanban"`,
          },
          {
            role: 'user',
            content: userMessage,
          },
        ],
        temperature: 0.7,
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error?.message || 'Erro ao processar mensagem');
    }

    messages.value.push({
      type: 'ai',
      content: data.choices[0].message.content,
    });
  } catch (error) {
    console.error('Erro ao processar mensagem:', error);
    messages.value.push({
      type: 'ai',
      content: 'Desculpe, ocorreu um erro ao processar sua mensagem.',
    });
  } finally {
    isLoading.value = false;
    scrollToBottom();
  }
};

// Nova função para lidar com a seleção da fonte
const handleSourceSelection = async source => {
  // Send telemetry for source selection
  await sendTelemetryEvent('source_selected', { source });

  showSourceSelector.value = false;
  selectedSource.value = source;
  isProcessingItems.value = true;

  try {
    if (source === 'contacts') {
      messages.value.push({
        type: 'ai',
        content: 'Ok, vou criar itens a partir dos contatos. Processando...',
      });

      const { data } = await ContactAPI.get(1);
      const count = await createItemsFromContacts(data.payload);

      messages.value.push({
        type: 'ai',
        content: `✅ Criei ${count} itens Kanban a partir dos contatos! Posso ajudar com mais alguma coisa?`,
      });
    } else if (source === 'conversations') {
      messages.value.push({
        type: 'ai',
        content: 'Ok, vou criar itens a partir das conversas. Processando...',
      });

      const response = await ConversationAPI.get();
      // Ajusta o acesso aos dados da conversa considerando a estrutura correta
      const conversations = response.data?.data?.payload || [];
      const count = await createItemsFromConversations(conversations);

      messages.value.push({
        type: 'ai',
        content: `✅ Criei ${count} itens Kanban a partir das conversas! Posso ajudar com mais alguma coisa?`,
      });
    }
  } catch (error) {
    console.error('Erro ao processar itens:', error);
    messages.value.push({
      type: 'ai',
      content: 'Desculpe, ocorreu um erro ao criar os itens.',
    });
  } finally {
    isProcessingItems.value = false;
    selectedSource.value = null;
  }
};

// Nova função para selecionar funil
const handleFunnelSelection = async funnel => {
  // Send telemetry for funnel selection
  await sendTelemetryEvent('funnel_selected', {
    funnel_id: funnel.id,
    funnel_name: funnel.name,
  });

  selectedFunnel.value = funnel;
  showFunnelSelector.value = false;

  // Se não houver fonte selecionada, significa que é uma análise
  if (!selectedSource.value) {
    await analyzeFunnelFlow(funnel);
  } else {
    // Caso contrário, continua com o fluxo de criação de itens
    showSourceSelector.value = true;
    messages.value.push({
      type: 'ai',
      content: 'Agora, selecione a fonte dos dados para criar os itens:',
    });
  }
  scrollToBottom();
};

const scrollToBottom = () => {
  if (messagesContainer.value) {
    setTimeout(() => {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight;
    }, 100);
  }
};

onMounted(async () => {
  await loadOpenAIConfig();
});

const quickPrompts = [
  {
    id: 'generate',
    title: 'Gerar Itens',
    icon: 'add',
    description: 'Crie novos itens Kanban baseados em seus requisitos',
    action: 'generate_items',
  },
  {
    id: 'optimize',
    title: 'Otimizar Fluxo',
    icon: 'arrow-clockwise',
    description: 'Receba sugestões para melhorar seu fluxo de trabalho',
    action: 'analyze_flow',
  },
  {
    id: 'schedule',
    title: 'Agenda Inteligente',
    icon: 'calendar',
    description: 'Agendamento e priorização de tarefas com IA',
    prompt: 'Ajude-me a agendar e priorizar meus itens Kanban',
    disabled: true,
    comingSoon: true,
  },
  {
    id: 'analyze',
    title: 'Analisar Quadro',
    icon: 'arrow-trending-lines',
    description: 'Obtenha insights sobre o desempenho do seu quadro',
    prompt: 'Analise as métricas do meu quadro Kanban e forneça insights',
    disabled: true,
    comingSoon: true,
  },
];

const handleQuickAction = async action => {
  // Send telemetry for quick action
  await sendTelemetryEvent('quick_action_used', { action_id: action.id });

  if (action.action === 'generate_items') {
    await fetchFunnels();
    if (funnels.value.length === 0) {
      messages.value.push({
        type: 'ai',
        content: 'Nenhum funil encontrado. Por favor, crie um funil primeiro.',
      });
      return;
    }
    selectedSource.value = 'generate'; // Indica que é geração de itens
    showFunnelSelector.value = true;
    messages.value.push({
      type: 'ai',
      content: 'Primeiro, selecione o funil onde deseja criar os itens:',
    });
    scrollToBottom();
  } else if (action.id === 'optimize') {
    messages.value.push({
      type: 'ai',
      content: 'Vou ajudar você a otimizar seu fluxo de trabalho.',
    });
    await analyzeFunnels();
    scrollToBottom();
  } else {
    inputMessage.value = action.prompt;
    sendMessage();
  }
};

// Modifica a função para aplicar tanto mudanças de estrutura quanto templates
const applyFunnelSuggestions = async (funnelId, suggestion = null) => {
  try {
    const currentFunnel = funnels.value.find(
      f => String(f.id) === String(funnelId)
    );

    if (!currentFunnel) {
      throw new Error('Funil não encontrado');
    }

    let updatedStages = { ...currentFunnel.stages };

    if (suggestion.category === 'ESTRUTURA') {
      const stageId = suggestion.stage_data.name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_');

      if (suggestion.title.toLowerCase().includes('adicionar')) {
        // Adiciona nova etapa
        updatedStages = {
          ...updatedStages,
          [stageId]: {
            name: suggestion.stage_data.name,
            color: suggestion.stage_data.color,
            position: suggestion.stage_data.position,
            description: suggestion.stage_data.description,
          },
        };
      } else if (suggestion.title.toLowerCase().includes('remover')) {
        // Remove etapa existente
        const { [stageId]: _, ...remainingStages } = updatedStages;
        updatedStages = remainingStages;
      } else if (suggestion.title.toLowerCase().includes('atualizar')) {
        // Atualiza etapa existente
        updatedStages[stageId] = {
          ...updatedStages[stageId],
          ...suggestion.stage_data,
        };
      }
    } else if (suggestion.category === 'TEMPLATE') {
      // Encontra a etapa alvo
      const targetStage = Object.entries(currentFunnel.stages).find(
        ([stageId, stage]) => {
          const stageName = stage.name.toLowerCase();
          const targetName = suggestion.target_stage.toLowerCase();
          return (
            stageName.includes(targetName) || targetName.includes(stageName)
          );
        }
      );

      if (!targetStage) {
        throw new Error(`Etapa "${suggestion.target_stage}" não encontrada`);
      }

      const [stageId, stage] = targetStage;

      // Adiciona o template
      updatedStages[stageId] = {
        ...stage,
        message_templates: [
          ...(stage.message_templates || []),
          {
            id: Date.now(),
            title: suggestion.title,
            content: suggestion.description,
            webhook: suggestion.webhook || {
              url: '',
              method: 'POST',
              enabled: false,
            },
            stage_id: stageId,
            funnel_id: String(funnelId),
            conditions: {
              rules: [],
              enabled: false,
            },
            created_at: new Date().toISOString(),
          },
        ],
      };
    }

    // Atualiza o funil
    const updatedFunnel = {
      ...currentFunnel,
      stages: updatedStages,
    };

    await FunnelAPI.update(currentFunnel.id, updatedFunnel);
    await store.dispatch('funnel/fetch');

    messages.value.push({
      type: 'ai',
      content: `✅ ${
        suggestion.category === 'ESTRUTURA'
          ? 'Funil atualizado'
          : 'Template adicionado'
      } com sucesso!`,
    });
  } catch (error) {
    console.error('Erro ao aplicar sugestão:', error);
    messages.value.push({
      type: 'ai',
      content:
        error.message || 'Desculpe, ocorreu um erro ao aplicar a sugestão.',
    });
  }
};

// Modifica a função analyzeFunnels para incluir seleção de funil
const analyzeFunnels = async () => {
  try {
    // Busca os funis primeiro
    await fetchFunnels();

    if (!funnels.value || funnels.value.length === 0) {
      messages.value.push({
        type: 'ai',
        content: 'Nenhum funil encontrado para análise.',
      });
      return;
    }

    messages.value.push({
      type: 'ai',
      content: 'Primeiro, selecione o funil que você deseja analisar:',
    });

    // Mostra o seletor de funil
    showFunnelSelector.value = true;
    selectedFunnel.value = null;
    selectedSource.value = null; // Limpa a fonte para indicar que é uma análise
  } catch (error) {
    console.error('Erro ao carregar funis:', error);
    messages.value.push({
      type: 'ai',
      content: 'Desculpe, ocorreu um erro ao carregar os funis.',
    });
  }
};

// Modifica o prompt do sistema para incluir sugestões de funil e templates
const analyzeFunnelFlow = async funnel => {
  try {
    // Array de etapas fictícias para o loading
    const analysisSteps = [
      'Analisando estrutura do funil...',
      'Verificando fluxo de trabalho...',
      'Identificando oportunidades de melhoria...',
      'Gerando sugestões personalizadas...',
      'Finalizando análise...',
    ];

    // Adiciona mensagem inicial com loading
    messages.value.push({
      type: 'ai',
      isLoading: true,
      content: {
        title: `Analisando o funil "${funnel.name}"`,
        steps: analysisSteps,
        currentStep: 0,
        progress: 0,
      },
    });

    // Simula progresso através das etapas
    for (let i = 0; i < analysisSteps.length; i++) {
      await new Promise(resolve => setTimeout(resolve, 1000));
      messages.value[messages.value.length - 1].content.currentStep = i;
      messages.value[messages.value.length - 1].content.progress =
        ((i + 1) / analysisSteps.length) * 100;
    }

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${openAIConfig.value.api_key}`,
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `Você é um especialista em otimização de funis Kanban.
                     Analise o funil e sugira melhorias em duas categorias:

                     1. ESTRUTURA (como no FunnelForm):
                     - Adicionar/Remover etapas
                     - Reordenar etapas
                     - Atualizar nomes e descrições
                     - Campos disponíveis: name, color, position, description
                     
                     2. TEMPLATE (como no MessageTemplateForm):
                     - Templates de mensagem para cada etapa
                     - Campos: title, content, webhook (opcional)
                     - Variáveis disponíveis:
                       {contact.name}, {contact.email}, {contact.phone}
                       {agent.name}, {stage.name}

                     IMPORTANTE: Retorne um JSON com o seguinte formato:
                     {
                       "suggestions": [
                         {
                           "title": "Título da sugestão",
                           "description": "Detalhes da implementação",
                           "category": "ESTRUTURA|TEMPLATE",
                           "target_stage": "nome_da_etapa", // Para TEMPLATE
                           "stage_data": {  // Para ESTRUTURA
                             "name": "Nome da Etapa",
                             "color": "#HEX",
                             "position": 1,
                             "description": "Descrição"
                           },
                           "current_state": "Estado atual",
                           "expected_state": "Estado após implementação",
                           "impact": "HIGH|MEDIUM|LOW",
                           "implementation": "EASY|MEDIUM|HARD"
                         }
                       ]
                     }`,
          },
          {
            role: 'user',
            content: `Analise este funil e sugira melhorias:
                     ${JSON.stringify(funnel, null, 2)}
                     
                     Considere:
                     - Tipo do funil: ${funnel.name}
                     - Etapas atuais: ${Object.values(funnel.stages)
                       .map(s => s.name)
                       .join(', ')}
                     - Etapas sem descrição: ${
                       Object.values(funnel.stages).filter(s => !s.description)
                         .length
                     }
                     - Etapas com templates: ${
                       Object.values(funnel.stages).filter(
                         s => s.message_templates?.length > 0
                       ).length
                     }
                     
                     Sugira tanto melhorias na estrutura do funil quanto templates de mensagem apropriados.`,
          },
        ],
        temperature: 0.3,
      }),
    });

    const aiData = await response.json();
    const cleanContent = aiData.choices[0].message.content
      .replace(/```json\s*/g, '')
      .replace(/```\s*/g, '')
      .replace(/^\s*{\s*/, '{')
      .replace(/\s*}\s*$/, '}')
      .trim();

    let analysis;
    try {
      analysis = JSON.parse(cleanContent);
    } catch (parseError) {
      console.error('Erro ao parsear JSON:', parseError);
      console.log('Conteúdo que falhou:', cleanContent);
      throw new Error('Falha ao processar resposta da IA');
    }

    // Atualiza o template para mostrar o estado atual vs. esperado
    messages.value.push({
      type: 'ai',
      content: 'Aqui estão os problemas identificados e suas soluções:',
    });

    analysis.suggestions.forEach((suggestion, index) => {
      messages.value.push({
        type: 'ai',
        isCard: true,
        content: {
          title: suggestion.title,
          description: suggestion.description,
          category: suggestion.category,
          impact: suggestion.impact,
          implementation: suggestion.implementation,
          currentState: suggestion.current_state,
          expectedState: suggestion.expected_state,
        },
        actions: [
          {
            label: 'Aplicar esta solução',
            value: `apply_${index}`,
            style: 'primary',
            suggestion,
          },
          {
            label: 'Ignorar',
            value: `ignore_${index}`,
            style: 'secondary',
          },
        ],
      });
    });
  } catch (error) {
    console.error('Erro ao analisar funil:', error);
    messages.value.push({
      type: 'ai',
      content:
        'Desculpe, ocorreu um erro ao analisar o funil. Por favor, tente novamente.',
    });
  }
};

// Modifica o handler de ações para lidar com as sugestões individuais
const handleMessageAction = async (action, message) => {
  if (action.value === 'apply_all') {
    await applyFunnelSuggestions(selectedFunnel.value.id);
  } else if (action.value.startsWith('apply_')) {
    selectedSuggestion.value = action.suggestion;
    // Prepara visualização das mudanças
    pendingChanges.value = prepareChangesPreview(action.suggestion);
    showConfirmationModal.value = true;
  }
};

// Função para preparar preview das mudanças
const prepareChangesPreview = suggestion => {
  if (!suggestion) {
    throw new Error('Sugestão inválida');
  }

  const changes = {
    type: suggestion.category,
    fields: [],
  };

  try {
    switch (suggestion.category) {
      case 'ESTRUTURA': {
        const actionType = suggestion.action?.toLowerCase() || t('AI.ADD');
        changes.fields.push({
          type: actionType,
          field: 'Etapa',
          details: [
            {
              label: 'Nome',
              value: suggestion.stage_data?.name || 'Não definido',
            },
            {
              label: 'Descrição',
              value: suggestion.stage_data?.description || 'Não definida',
            },
            {
              label: 'Posição',
              value:
                suggestion.stage_data?.position?.toString() || 'Não definida',
            },
            { label: 'Cor', value: suggestion.stage_data?.color || '#000000' },
          ],
        });
        break;
      }

      case 'TEMPLATE': {
        changes.fields.push({
          type: 'add',
          field: 'Template de Mensagem',
          details: [
            { label: 'Título', value: suggestion.title || 'Não definido' },
            { label: 'Conteúdo', value: suggestion.content || 'Não definido' },
            {
              label: 'Etapa',
              value: suggestion.target_stage || 'Não definida',
            },
            {
              label: 'Webhook',
              value: suggestion.webhook?.enabled ? 'Ativado' : 'Desativado',
            },
          ],
        });
        break;
      }

      default:
        throw new Error(
          `Tipo de sugestão desconhecido: ${suggestion.category}`
        );
    }

    return changes;
  } catch (error) {
    console.error('Erro ao preparar preview das mudanças:', error);
    throw new Error('Não foi possível preparar o preview das mudanças');
  }
};

// Funções auxiliares para classes dos badges
const getCategoryClass = category => {
  return category?.toLowerCase().replace('_', '-') || '';
};

const getImpactClass = impact => {
  return impact?.toLowerCase() || '';
};

const getImplementationClass = implementation => {
  return implementation?.toLowerCase() || '';
};

// Função para confirmar e aplicar as mudanças
const confirmChanges = async () => {
  try {
    await applyFunnelSuggestions(
      selectedFunnel.value.id,
      selectedSuggestion.value
    );
    showConfirmationModal.value = false;
    selectedSuggestion.value = null;
    pendingChanges.value = null;
  } catch (error) {
    console.error('Erro ao aplicar mudanças:', error);
  }
};

const sendTelemetryEvent = async (eventName, eventData = {}) => {
  try {
    const baseUrl = 'https://api.os.stacklab.digital/api';
    const eventsUrl = `${baseUrl}/events`;
    const installationData = {
      installation_identifier:
        window.installationConfig?.installationIdentifier ||
        store.state.globalConfig.installationIdentifier,
      installation_version:
        window.installationConfig?.version || store.state.globalConfig.version,
      installation_host: window.location.hostname,
      installation_env: process.env.NODE_ENV,
      edition:
        window.installationConfig?.edition || store.state.globalConfig.edition,
      account_id: accountId,
      user_id: store.state.auth.currentUser?.id,
      user_role: store.state.auth.currentUser?.role,
    };

    const info = {
      event_name: `kanban_ai_${eventName}`,
      event_data: {
        ...eventData,
        ...installationData,
        component: 'KanbanAI',
        timestamp: new Date().toISOString(),
      },
    };

    await fetch(eventsUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify(info),
    });
  } catch (error) {
    // Silently fail to not disrupt user experience
    console.error('Telemetry error:', error);
  }
};

// Função para alternar o estado de colapso das ações rápidas
const toggleQuickActions = () => {
  isQuickActionsCollapsed.value = !isQuickActionsCollapsed.value;
};
</script>

<template>
  <div class="kanban-ai-container">
    <!-- Header -->
    <header class="ai-header">
      <div class="flex items-center gap-3">
        <div class="header-avatar">
          <img
            src="https://img.freepik.com/free-psd/cute-3d-robot-waving-hand-cartoon-vector-icon-illustration-people-technology-isolated-flat-vector_138676-10649.jpg"
            alt="AI Avatar"
            class="header-avatar-image"
          />
        </div>
        <div class="header-text">
          <h2
            class="text-lg relative z-10 font-semibold tracking-wide text-white"
          >
            Assistente Kanban AI
          </h2>
          <p class="text-sm text-white/80 font-normal">
            Otimize seu fluxo de trabalho com ajuda da IA
          </p>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <div class="ai-content">
      <!-- Quick Actions -->
      <div class="quick-actions">
        <div class="flex justify-between items-center mb-4">
          <h3 class="section-title">Ações Rápidas</h3>
          <button class="toggle-text-button" @click="toggleQuickActions">
            {{ isQuickActionsCollapsed ? 'Expandir' : 'Colapsar' }}
          </button>
        </div>
        <div v-show="!isQuickActionsCollapsed" class="actions-grid -mt-1">
          <button
            v-for="action in quickPrompts"
            :key="action.id"
            class="action-card group"
            :class="{ disabled: action.disabled }"
            :disabled="action.disabled"
            @click="handleQuickAction(action)"
          >
            <div class="action-icon">
              <fluent-icon :icon="action.icon" size="18" />
            </div>
            <div class="action-content">
              <div class="flex items-center justify-between gap-2 mb-1">
                <span class="action-title">{{ action.title }}</span>
                <span v-if="action.comingSoon" class="coming-soon-badge">
                  Em breve
                </span>
              </div>
              <p class="action-description">{{ action.description }}</p>
            </div>
          </button>
        </div>
      </div>

      <!-- AI Chat -->
      <div class="ai-chat">
        <h3 class="section-title">Assistente IA</h3>
        <div class="chat-container">
          <div ref="messagesContainer" class="chat-messages">
            <div
              v-for="(message, index) in messages"
              :key="index"
              class="message"
              :class="[message.type]"
            >
              <div v-if="message.type === 'ai'" class="avatar">
                <img
                  src="https://img.freepik.com/free-psd/cute-3d-robot-waving-hand-cartoon-vector-icon-illustration-people-technology-isolated-flat-vector_138676-10649.jpg"
                  alt="AI Avatar"
                  class="avatar-image"
                />
              </div>
              <div class="message-content">
                <!-- Card interativo para sugestões -->
                <div v-if="message.isCard" class="suggestion-card">
                  <div class="suggestion-header">
                    <h4 class="suggestion-title">
                      {{ message.content.title }}
                    </h4>
                    <div class="suggestion-badges">
                      <span
                        class="badge category-badge"
                        :class="getCategoryClass(message.content.category)"
                      >
                        {{ message.content.category }}
                      </span>

                      <span
                        class="badge impact-badge"
                        :class="getImpactClass(message.content.impact)"
                      >
                        {{ message.content.impact }}
                      </span>

                      <span
                        class="badge implementation-badge"
                        :class="
                          getImplementationClass(message.content.implementation)
                        "
                      >
                        {{ message.content.implementation }}
                      </span>
                    </div>
                  </div>

                  <div class="suggestion-states">
                    <div class="current-state">
                      <span class="state-label">Estado Atual:</span>
                      <p class="state-description">
                        {{ message.content.currentState }}
                      </p>
                    </div>
                    <div class="expected-state">
                      <span class="state-label">Estado Esperado:</span>
                      <p class="state-description">
                        {{ message.content.expectedState }}
                      </p>
                    </div>
                  </div>

                  <div class="suggestion-solution">
                    <span class="solution-label">Solução Proposta:</span>
                    <p class="solution-description">
                      {{ message.content.description }}
                    </p>
                  </div>

                  <div class="suggestion-actions">
                    <woot-button
                      v-for="action in message.actions"
                      :key="action.value"
                      :variant="action.style"
                      size="small"
                      class="action-button"
                      @click="handleMessageAction(action, message)"
                    >
                      {{ action.label }}
                    </woot-button>
                  </div>
                </div>
                <!-- Conteúdo normal da mensagem -->
                <div v-else-if="message.isLoading" class="loading-analysis">
                  <h4 class="loading-title">{{ message.content.title }}</h4>
                  <div class="loading-steps">
                    <div
                      v-for="(step, index) in message.content.steps"
                      :key="index"
                      class="loading-step"
                      :class="{
                        completed: index < message.content.currentStep,
                        current: index === message.content.currentStep,
                      }"
                    >
                      <div class="step-indicator">
                        <span
                          v-if="index < message.content.currentStep"
                          class="check-icon"
                        >
                          ✓
                        </span>
                        <span
                          v-else-if="index === message.content.currentStep"
                          class="pulse-icon"
                        />
                        <span v-else class="waiting-icon" />
                      </div>
                      <span class="step-text">{{ step }}</span>
                    </div>
                  </div>
                  <div class="progress-bar">
                    <div
                      class="progress-fill"
                      :style="{ width: `${message.content.progress}%` }"
                    />
                  </div>
                </div>
                <p v-else>{{ message.content }}</p>
                <!-- Adiciona o seletor de funil -->
                <div
                  v-if="
                    showFunnelSelector &&
                    message === messages[messages.length - 1]
                  "
                  class="source-selector"
                >
                  <button
                    v-for="funnel in funnels"
                    :key="funnel.id"
                    class="source-button"
                    @click="handleFunnelSelection(funnel)"
                  >
                    <span class="icon">📊</span>
                    {{ funnel.name }}
                  </button>
                </div>
                <!-- Seletor de fonte existente -->
                <div
                  v-if="
                    showSourceSelector &&
                    message === messages[messages.length - 1]
                  "
                  class="source-selector"
                >
                  <button
                    class="source-button"
                    @click="handleSourceSelection('contacts')"
                  >
                    <span class="icon">👥</span>
                    Contatos
                  </button>
                  <button
                    class="source-button"
                    @click="handleSourceSelection('conversations')"
                  >
                    <span class="icon">💬</span>
                    Conversas
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div class="chat-input-container">
            <div v-if="isLoading" class="typing-indicator">
              IA está pensando...
            </div>
            <div class="chat-input">
              <input
                v-model="inputMessage"
                type="text"
                placeholder="Pergunte qualquer coisa sobre seu quadro Kanban..."
                class="ai-input"
                @keyup.enter="sendMessage"
              />
              <button
                class="send-button"
                :disabled="isLoading || !inputMessage.trim()"
                @click="sendMessage"
              >
                <svg
                  width="20"
                  height="20"
                  viewBox="0 0 24 24"
                  fill="none"
                  xmlns="http://www.w3.org/2000/svg"
                  class="send-icon"
                >
                  <path
                    d="M22 2L11 13"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                  <path
                    d="M22 2L15 22L11 13L2 9L22 2Z"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Add modal component -->
    <AIConfigModal v-if="showConfigModal" @close="showConfigModal = false" />

    <!-- Add confirmation modal component -->
    <Modal
      v-if="showConfirmationModal"
      :show="showConfirmationModal"
      :on-close="() => (showConfirmationModal = false)"
    >
      <div class="p-6">
        <div class="mb-6">
          <h3 class="text-lg font-medium mb-2">Confirmar Alterações</h3>
          <p class="text-sm text-slate-600 dark:text-slate-400">
            As seguintes alterações serão aplicadas ao funil:
          </p>
        </div>

        <div class="changes-preview mb-6">
          <!-- Tipo de Alteração -->
          <div class="change-category mb-4">
            <span
              class="badge category-badge"
              :class="getCategoryClass(pendingChanges?.type)"
            >
              {{ pendingChanges?.type }}
            </span>
          </div>

          <!-- Lista de Alterações -->
          <div
            v-for="(field, index) in pendingChanges?.fields"
            :key="index"
            class="change-field"
          >
            <div class="change-field-header">
              <span class="change-type-badge" :class="field.type">
                {{ field.type === 'add' ? 'Adicionar' : 'Atualizar' }}
              </span>
              <span class="field-name">{{ field.field }}</span>
            </div>

            <div class="change-details">
              <div
                v-for="(detail, idx) in field.details"
                :key="idx"
                class="detail-item"
              >
                <span class="detail-label">{{ detail.label }}:</span>
                <span class="detail-value">{{ detail.value }}</span>
                <span v-if="detail.affected" class="detail-affected">
                  Afeta: {{ detail.affected }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="flex justify-end gap-2">
          <woot-button variant="clear" @click="showConfirmationModal = false">
            Cancelar
          </woot-button>
          <woot-button variant="primary" @click="confirmChanges">
            Confirmar e Aplicar
          </woot-button>
        </div>
      </div>
    </Modal>
  </div>
</template>

<style lang="scss" scoped>
.kanban-ai-container {
  @apply flex flex-col h-full bg-white dark:bg-slate-900;
}

.ai-header {
  @apply flex items-center justify-between p-6 relative overflow-hidden;
  background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%);

  &::before {
    content: '';
    @apply absolute inset-0 opacity-10;
    background-image: radial-gradient(
      circle at 50% 0,
      rgba(255, 255, 255, 0.3) 0%,
      rgba(255, 255, 255, 0.1) 50%,
      transparent 100%
    );
  }

  &::after {
    content: '';
    @apply absolute inset-0 border-b border-white/10;
  }

  .header-text {
    @apply flex flex-col gap-0.5;

    h2 {
      @apply text-lg relative z-10 font-semibold tracking-wide;
      text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
    }

    p {
      @apply relative z-10;
      text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
    }
  }

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-4;

    .header-text {
      h2 {
        @apply text-base;
      }

      p {
        @apply text-xs;
      }
    }
  }

  @media (max-width: 480px) {
    @apply p-3;

    .header-text {
      h2 {
        @apply text-sm;
      }

      p {
        @apply text-xs;
      }
    }
  }
}

.header-avatar {
  @apply flex-shrink-0 relative z-10;

  .header-avatar-image {
    @apply w-10 h-10 rounded-lg object-cover bg-white/10
      ring-2 ring-white/20 shadow-lg;
    filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.1));
  }

  /* Mobile styles */
  @media (max-width: 480px) {
    .header-avatar-image {
      @apply w-8 h-8;
    }
  }
}

.ai-content {
  @apply flex-1 p-6 space-y-6 overflow-y-auto;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-4 space-y-4;
  }

  @media (max-width: 480px) {
    @apply p-3 space-y-3;
  }
}

.section-title {
  @apply text-base font-medium text-slate-800 dark:text-slate-200;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply text-sm;
  }

  @media (max-width: 480px) {
    @apply text-sm;
  }
}

.toggle-text-button {
  @apply text-sm font-medium text-slate-600 dark:text-slate-400 
    hover:text-woot-600 dark:hover:text-woot-400 
    transition-colors duration-200 cursor-pointer
    px-2 py-1 rounded-md hover:bg-slate-100 dark:hover:bg-slate-800;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply text-xs px-1.5 py-0.5;
  }

  @media (max-width: 480px) {
    @apply text-xs px-1 py-0.5;
  }
}

.actions-grid {
  @apply grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply grid-cols-2 gap-2;
  }

  @media (max-width: 480px) {
    @apply grid-cols-1 gap-2;
  }
}

.action-card {
  @apply flex items-start gap-3 p-4 rounded-xl border border-slate-200/50
    dark:border-slate-700/50 hover:border-woot-500/50 dark:hover:border-woot-500/50
    transition-all duration-300 bg-white dark:bg-slate-800/90 text-left
    hover:shadow-lg hover:shadow-slate-200/20 dark:hover:shadow-slate-900/30
    relative overflow-hidden min-h-[110px];

  &.disabled {
    @apply opacity-80 cursor-not-allowed hover:border-slate-200/50
      dark:hover:border-slate-700/50 hover:shadow-none;

    .action-icon {
      @apply opacity-50;
    }
  }

  .action-icon {
    @apply flex items-center justify-center w-8 h-8 rounded-md flex-shrink-0
      bg-gradient-to-br from-n-iris-3 to-n-iris-4 
      dark:from-n-iris-8 dark:to-n-iris-9
      text-n-iris-9 dark:text-n-iris-4
      transition-transform duration-300
      ring-1 ring-slate-200/50 dark:ring-slate-700/50;

    .group:not(.disabled) &:hover {
      @apply scale-110;
    }
  }

  .action-content {
    @apply flex-1 min-w-0 flex flex-col justify-center gap-2;

    .action-title {
      @apply text-xs font-semibold text-slate-900 dark:text-slate-100
        transition-colors duration-300 truncate;
    }

    .action-description {
      @apply text-[11px] text-slate-500 dark:text-slate-400 line-clamp-2
        transition-colors duration-300;
    }

    .coming-soon-badge {
      @apply inline-flex items-center px-2 py-0.5 text-[9px] font-medium 
              rounded-full bg-gradient-to-r from-n-amber-3 to-n-amber-4 
      dark:from-n-amber-8 dark:to-n-amber-9
      text-n-amber-9 dark:text-n-amber-2
        ring-1 ring-n-amber-4/50 dark:ring-n-amber-8/50
        flex-shrink-0
        transition-all duration-300;
    }
  }

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-3 gap-2 min-h-[90px];

    .action-icon {
      @apply w-7 h-7;
    }

    .action-content {
      .action-title {
        @apply text-xs;
      }

      .action-description {
        @apply text-[10px];
      }
    }
  }

  @media (max-width: 480px) {
    @apply p-2 gap-2 min-h-[80px];

    .action-icon {
      @apply w-6 h-6;
    }

    .action-content {
      .action-title {
        @apply text-xs;
      }

      .action-description {
        @apply text-[9px];
      }
    }
  }
}

.chat-container {
  @apply flex flex-col h-[400px] bg-slate-50 dark:bg-slate-800/50 rounded-xl border
    border-slate-200 dark:border-slate-700;
  height: calc(100vh - 400px);
  min-height: 450px;
  max-height: 600px;

  /* Mobile styles */
  @media (max-width: 768px) {
    height: calc(100vh - 300px);
    min-height: 350px;
    max-height: 500px;
  }

  @media (max-width: 480px) {
    height: calc(100vh - 250px);
    min-height: 300px;
    max-height: 450px;
  }
}

.chat-messages {
  @apply flex-1 p-6 space-y-6 overflow-y-auto;
  height: calc(100% - 80px);

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-4 space-y-4;
  }

  @media (max-width: 480px) {
    @apply p-3 space-y-3;
  }
}

.message {
  @apply flex gap-2 mb-4;

  &.ai {
    @apply flex-row;
    .message-content {
      @apply shadow-sm
        border border-slate-200/50 dark:border-slate-700/50
        backdrop-blur-sm;
      background: linear-gradient(120deg, #ffffff 0%, #f8f9ff 100%);

      &.dark {
        background: linear-gradient(120deg, #1e293b 0%, #1e1f2d 100%);
      }
    }
  }

  &.user {
    @apply flex-row-reverse;
    .message-content {
      @apply bg-gradient-to-br from-n-iris-9 to-n-iris-10 text-white;
    }
  }

  .avatar {
    @apply flex-shrink-0;

    .avatar-image {
      @apply w-8 h-8 rounded-full object-cover bg-white
        ring-2 ring-n-iris-3 dark:ring-n-iris-9/30;
    }
  }

  .message-content {
    @apply px-4 py-3 rounded-2xl max-w-[80%] relative
      transition-all duration-200;

    /* Triângulo do bubble */
    &::before {
      content: '';
      @apply absolute top-3 w-2 h-2 transform rotate-45;
    }
  }

  /* Posicionamento do triângulo baseado no tipo de mensagem */
  &.ai .message-content::before {
    @apply -left-1 bg-white dark:bg-slate-800
      border-l border-b border-slate-200/50 dark:border-slate-700/50;
  }

  &.user .message-content::before {
    @apply -right-1 bg-n-iris-9;
  }

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply gap-2 mb-3;

    .avatar .avatar-image {
      @apply w-7 h-7;
    }

    .message-content {
      @apply px-3 py-2 max-w-[85%] text-sm;

      &::before {
        @apply top-2 w-1.5 h-1.5;
      }
    }
  }

  @media (max-width: 480px) {
    @apply gap-1.5 mb-2;

    .avatar .avatar-image {
      @apply w-6 h-6;
    }

    .message-content {
      @apply px-2.5 py-2 max-w-[90%] text-xs;

      &::before {
        @apply top-1.5 w-1 h-1;
      }
    }
  }
}

.chat-input-container {
  @apply flex items-center p-4 border-t border-slate-200 dark:border-slate-700;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-3;
  }

  @media (max-width: 480px) {
    @apply p-2;
  }
}

.typing-indicator {
  @apply text-sm text-slate-500 dark:text-slate-400 mb-2 animate-pulse;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-xs mb-1;
  }
}

.chat-input {
  @apply flex w-full;

  .ai-input {
    @apply flex-1 px-4 text-sm rounded-xl my-auto
      bg-white dark:bg-slate-800
      border border-slate-200 dark:border-slate-700
      focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500;
    height: 40px;
  }

  .send-button {
    @apply flex items-center justify-center text-white rounded-xl ml-2 my-auto
      bg-gradient-to-r from-n-iris-9 to-n-iris-10
      hover:from-n-iris-10 hover:to-n-iris-11
      disabled:opacity-50 disabled:cursor-not-allowed
      transition-all duration-300;
    height: 40px;
    width: 40px;
  }

  .send-icon {
    @apply transition-transform duration-300;
  }

  &:hover:not(:disabled) {
    @apply shadow-lg shadow-n-iris-9/25;
    .send-icon {
      @apply -translate-y-px scale-110;
    }
  }

  &:active:not(:disabled) {
    @apply shadow-md shadow-n-iris-9/20;
    .send-icon {
      @apply translate-y-0 scale-105;
    }
  }

  /* Mobile styles */
  @media (max-width: 768px) {
    .ai-input {
      @apply px-3 text-sm;
      height: 36px;
    }

    .send-button {
      height: 36px;
      width: 36px;
    }
  }

  @media (max-width: 480px) {
    .ai-input {
      @apply px-2.5 text-xs;
      height: 32px;
    }

    .send-button {
      height: 32px;
      width: 32px;
    }

    .send-icon {
      @apply w-4 h-4;
    }
  }
}

.source-selector {
  @apply flex flex-wrap gap-2 mt-4;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply gap-1.5 mt-3;
  }

  @media (max-width: 480px) {
    @apply gap-1 mt-2;
  }
}

.source-button {
  @apply flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium
    bg-white dark:bg-slate-700 border border-slate-200 dark:border-slate-600
    hover:border-woot-500 dark:hover:border-woot-500 transition-colors;

  .icon {
    @apply text-lg;
  }

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply px-3 py-1.5 text-xs gap-1.5;

    .icon {
      @apply text-base;
    }
  }

  @media (max-width: 480px) {
    @apply px-2.5 py-1 text-xs gap-1;

    .icon {
      @apply text-sm;
    }
  }
}

.message-actions {
  @apply flex gap-2 mt-4;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply gap-1.5 mt-3;
  }

  @media (max-width: 480px) {
    @apply gap-1 mt-2;
  }
}

.action-button {
  @apply text-sm;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-xs;
  }
}

.suggestion-card {
  @apply bg-white dark:bg-slate-800 rounded-lg p-4 border border-slate-200
    dark:border-slate-700 hover:border-woot-500 dark:hover:border-woot-500
    transition-all duration-200;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-3;
  }

  @media (max-width: 480px) {
    @apply p-2;
  }
}

.suggestion-title {
  @apply text-lg font-medium text-slate-900 dark:text-slate-100 mb-2;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply text-base mb-1.5;
  }

  @media (max-width: 480px) {
    @apply text-sm mb-1;
  }
}

.suggestion-description {
  @apply text-sm text-slate-600 dark:text-slate-400 mb-4 whitespace-pre-line;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply text-xs mb-3;
  }

  @media (max-width: 480px) {
    @apply text-xs mb-2;
  }
}

.suggestion-actions {
  @apply flex gap-2 justify-end;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply gap-1.5;
  }

  @media (max-width: 480px) {
    @apply gap-1;
  }
}

.suggestion-header {
  @apply flex flex-wrap items-start justify-between gap-2 mb-3;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply gap-1.5 mb-2;
  }

  @media (max-width: 480px) {
    @apply gap-1 mb-1.5;
  }
}

.suggestion-badges {
  @apply flex flex-wrap gap-2;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply gap-1.5;
  }

  @media (max-width: 480px) {
    @apply gap-1;
  }
}

.badge {
  @apply px-2 py-1 text-xs font-medium rounded-full;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply px-1.5 py-0.5 text-[10px];
  }
}

/* Estilos para badges de categoria */
.category-badge {
  &.estrutura {
    @apply bg-n-iris-3/50 text-n-iris-9;
    &.dark {
      @apply bg-n-iris-8/20 text-n-iris-3;
    }
  }
  &.descricao {
    @apply bg-n-teal-3/50 text-n-teal-9;
    &.dark {
      @apply bg-n-teal-8/20 text-n-teal-3;
    }
  }
  &.gargalo {
    @apply bg-n-ruby-3/50 text-n-ruby-9;
    &.dark {
      @apply bg-n-ruby-8/20 text-n-ruby-3;
    }
  }
  &.automacao {
    @apply bg-n-iris-3/50 text-n-iris-9;
    &.dark {
      @apply bg-n-iris-8/20 text-n-iris-3;
    }
  }
  &.boa-pratica {
    @apply bg-n-amber-3/50 text-n-amber-9;
    &.dark {
      @apply bg-n-amber-8/20 text-n-amber-2;
    }
  }
}

/* Estilos para badges de impacto */
.impact-badge {
  &.high {
    @apply bg-n-ruby-3/50 text-n-ruby-9;
    &.dark {
      @apply bg-n-ruby-8/20 text-n-ruby-3;
    }
  }
  &.medium {
    @apply bg-n-amber-3/50 text-n-amber-9;
    &.dark {
      @apply bg-n-amber-9/20 text-n-amber-3;
    }
  }
  &.low {
    @apply bg-n-teal-3/50 text-n-teal-9;
    &.dark {
      @apply bg-n-teal-9/20 text-n-teal-3;
    }
  }
}

/* Estilos para badges de implementação */
.implementation-badge {
  &.easy {
    @apply bg-n-teal-3/50 text-n-teal-9;
    &.dark {
      @apply bg-n-teal-9/20 text-n-teal-3;
    }
  }
  &.medium {
    @apply bg-n-amber-3/50 text-n-amber-9;
    &.dark {
      @apply bg-n-amber-9/20 text-n-amber-3;
    }
  }
  &.hard {
    @apply bg-n-ruby-3/50 text-n-ruby-9;
    &.dark {
      @apply bg-n-ruby-8/20 text-n-ruby-3;
    }
  }
}

.suggestion-states {
  @apply grid grid-cols-1 md:grid-cols-2 gap-4 mb-4;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply gap-3 mb-3;
  }

  @media (max-width: 480px) {
    @apply gap-2 mb-2;
  }
}

.current-state,
.expected-state {
  @apply p-3 rounded-lg;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-2;
  }

  @media (max-width: 480px) {
    @apply p-1.5;
  }
}

.current-state {
  @apply bg-n-ruby-3/50 dark:bg-n-ruby-9/20;
}

.expected-state {
  @apply bg-n-teal-3/50 dark:bg-n-teal-9/20;
}

.state-label,
.solution-label {
  @apply block text-xs font-medium text-slate-700 dark:text-slate-300 mb-1;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-[10px] mb-0.5;
  }
}

.state-description,
.solution-description {
  @apply text-sm text-slate-600 dark:text-slate-400;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-xs;
  }
}

.suggestion-solution {
  @apply mb-4 p-3 rounded-lg bg-slate-50 dark:bg-slate-800/20;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply mb-3 p-2;
  }

  @media (max-width: 480px) {
    @apply mb-2 p-1.5;
  }
}

.changes-preview {
  @apply bg-slate-50 dark:bg-slate-800/50 rounded-lg p-4;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-3;
  }

  @media (max-width: 480px) {
    @apply p-2;
  }
}

.change-field {
  @apply mb-4 last:mb-0;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply mb-3;
  }

  @media (max-width: 480px) {
    @apply mb-2;
  }
}

.change-field-header {
  @apply flex items-center gap-2 mb-2;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply gap-1.5 mb-1.5;
  }
}

.change-type-badge {
  @apply px-2 py-1 text-xs font-medium rounded-full;

  &.add {
    @apply bg-green-100 text-green-700 dark:bg-green-900/20 dark:text-green-300;
  }

  &.update {
    @apply bg-woot-100 text-woot-700 dark:bg-woot-900/20 dark:text-woot-300;
  }

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply px-1.5 py-0.5 text-[10px];
  }
}

.field-name {
  @apply text-sm font-medium text-slate-700 dark:text-slate-300;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-xs;
  }
}

.change-details {
  @apply bg-white dark:bg-slate-800 rounded-lg p-3 space-y-2;

  /* Mobile styles */
  @media (max-width: 768px) {
    @apply p-2 space-y-1.5;
  }

  @media (max-width: 480px) {
    @apply p-1.5 space-y-1;
  }
}

.detail-item {
  @apply flex flex-col text-sm;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-xs;
  }
}

.detail-label {
  @apply text-slate-500 dark:text-slate-400;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-[10px];
  }
}

.detail-value {
  @apply font-medium text-slate-700 dark:text-slate-300;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-xs;
  }
}

.detail-affected {
  @apply text-xs text-slate-500 dark:text-slate-400 mt-1;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply text-[10px] mt-0.5;
  }
}

.coming-soon-badge {
  @apply inline-flex px-2 py-0.5 text-[9px] font-medium rounded-full
    bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-200
    self-start;

  /* Mobile styles */
  @media (max-width: 480px) {
    @apply px-1.5 py-0.5 text-[8px];
  }
}

.loading-analysis {
  @apply space-y-4;

  .loading-title {
    @apply text-lg font-medium text-slate-900 dark:text-slate-100;

    /* Mobile styles */
    @media (max-width: 768px) {
      @apply text-base;
    }

    @media (max-width: 480px) {
      @apply text-sm;
    }
  }

  .loading-steps {
    @apply space-y-3;

    /* Mobile styles */
    @media (max-width: 768px) {
      @apply space-y-2;
    }

    @media (max-width: 480px) {
      @apply space-y-1.5;
    }
  }

  .loading-step {
    @apply flex items-center gap-3 text-sm text-slate-500 dark:text-slate-400;

    &.completed {
      @apply text-green-600 dark:text-green-400;
      .step-indicator {
        @apply bg-green-100 dark:bg-green-900/30;
        .check-icon {
          @apply text-green-600 dark:text-green-400;
        }
      }
    }

    &.current {
      @apply text-woot-600 dark:text-woot-400;
      .step-indicator {
        @apply bg-woot-100 dark:bg-woot-900/30;
      }
    }

    /* Mobile styles */
    @media (max-width: 768px) {
      @apply gap-2 text-xs;
    }

    @media (max-width: 480px) {
      @apply gap-1.5 text-xs;
    }
  }

  .step-indicator {
    @apply w-6 h-6 rounded-full bg-slate-100 dark:bg-slate-800
      flex items-center justify-center;

    /* Mobile styles */
    @media (max-width: 768px) {
      @apply w-5 h-5;
    }

    @media (max-width: 480px) {
      @apply w-4 h-4;
    }
  }

  .check-icon {
    @apply text-sm font-medium;

    /* Mobile styles */
    @media (max-width: 768px) {
      @apply text-xs;
    }

    @media (max-width: 480px) {
      @apply text-xs;
    }
  }

  .pulse-icon {
    @apply w-2 h-2 rounded-full bg-woot-500;
    animation: pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite;

    /* Mobile styles */
    @media (max-width: 480px) {
      @apply w-1.5 h-1.5;
    }
  }

  .waiting-icon {
    @apply w-2 h-2 rounded-full bg-slate-300 dark:bg-slate-600;

    /* Mobile styles */
    @media (max-width: 480px) {
      @apply w-1.5 h-1.5;
    }
  }

  .progress-bar {
    @apply h-1 bg-slate-100 dark:bg-slate-800 rounded-full overflow-hidden;

    /* Mobile styles */
    @media (max-width: 480px) {
      @apply h-0.5;
    }
  }

  .progress-fill {
    @apply h-full bg-gradient-to-r from-n-iris-9 to-n-iris-10;
    transition: width 0.5s ease-out;
  }
}

@keyframes pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.3;
  }
}

/* Mobile-specific optimizations */
@media (max-width: 768px) {
  .kanban-ai-container {
    @apply h-full;
  }

  /* Reduce spacing between sections */
  .ai-content > * + * {
    @apply mt-4;
  }

  /* Optimize chat container height */
  .chat-container {
    @apply flex-shrink;
  }
}

@media (max-width: 480px) {
  /* Further reduce spacing for very small screens */
  .ai-content > * + * {
    @apply mt-3;
  }

  /* Ensure buttons are touch-friendly */
  .source-button,
  .action-button {
    @apply min-h-[32px];
  }

  /* Optimize avatar sizes */
  .header-avatar-image,
  .avatar-image {
    @apply ring-1;
  }
}

/* Landscape mobile optimizations */
@media (max-width: 768px) and (orientation: landscape) {
  .ai-header {
    @apply p-3;
  }

  .ai-content {
    @apply p-3 space-y-3;
  }

  .chat-container {
    height: calc(100vh - 200px);
    min-height: 250px;
  }
}
</style>
