<template>
  <transition name="modal-fade">
    <div class="modal-backdrop">
      <div
        class="modal"
        role="dialog"
        aria-labelledby="modalTitle"
        aria-describedby="modalDescription"
      >
        <header class="modal-header" id="modalTitle">
          <div class="flex items-center gap-3">
            <h3>Configuração do Modelo AI</h3>
            <span
              :class="[
                'px-2 py-1 text-xs font-medium rounded-full',
                isConnected
                  ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                  : 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
              ]"
            >
              {{
                isConnected
                  ? t('KANBAN.AI_CONFIG.STATUS.CONNECTED')
                  : t('KANBAN.AI_CONFIG.STATUS.DISCONNECTED')
              }}
            </span>
          </div>
          <button
            type="button"
            class="btn-close"
            @click="$emit('close')"
            aria-label="Fechar modal"
          >
            ×
          </button>
        </header>

        <section class="modal-body" id="modalDescription">
          <div class="space-y-4">
            <div
              v-if="isConnected"
              class="p-4 bg-slate-50 dark:bg-slate-800/50 rounded-lg"
            >
              <p class="text-sm text-slate-600 dark:text-slate-400">
                Usando as credenciais configuradas no Chatwoot. Para alterar,
                acesse as
                <a
                  :href="settingsUrl"
                  target="_blank"
                  class="text-woot-500 hover:underline"
                >
                  configurações de integrações </a
                >.
              </p>
            </div>

            <div v-else class="form-group">
              <label class="block text-sm font-medium mb-1">API Key</label>
              <input
                type="password"
                class="w-full rounded-lg border p-2"
                placeholder="sk-..."
                v-model="apiKey"
              />
              <div
                class="mt-2 text-xs text-slate-500 dark:text-slate-400 space-y-2"
              >
                <p>Para obter sua API Key da OpenAI, siga os passos:</p>
                <ol class="list-decimal ml-4 space-y-1">
                  <li>
                    Acesse
                    <a
                      href="https://platform.openai.com/api-keys"
                      target="_blank"
                      class="text-woot-500 hover:underline"
                      >platform.openai.com/api-keys</a
                    >
                  </li>
                  <li>Faça login ou crie uma conta OpenAI</li>
                  <li>Clique em "Create new secret key"</li>
                  <li>Dê um nome para sua chave e copie o valor gerado</li>
                  <li>Cole a chave no campo acima</li>
                </ol>
                <p class="text-amber-500 dark:text-amber-400">
                  <strong>Importante:</strong> Guarde sua chave em local seguro.
                  Ela só será mostrada uma vez.
                </p>
              </div>
            </div>
            <div class="form-group">
              <label class="block text-sm font-medium mb-1">Modelo</label>
              <select
                class="w-full rounded-lg border p-2"
                v-model="selectedModel"
                disabled
              >
                <option value="gpt-4-mini">GPT-4 Mini</option>
              </select>
            </div>
          </div>
        </section>

        <footer class="modal-footer">
          <button type="button" class="btn-save" @click="handleSave">
            Salvar
          </button>
        </footer>
      </div>
    </div>
  </transition>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';

const router = useRouter();
const emit = defineEmits(['close']);
const apiKey = ref('');
const selectedModel = ref('gpt-4-mini');
const isConnected = ref(false);

const accountId = router.currentRoute.value.params.accountId;
const settingsUrl = `/app/accounts/${accountId}/settings/integrations/openai`;

onMounted(async () => {
  try {
    // Verifica se existe integração configurada usando a rota correta do Chatwoot
    const response = await window.axios.get(
      `/api/v1/accounts/${accountId}/integrations/apps`
    );

    const openaiIntegration = response.data?.payload?.find(
      integration => integration.id === 'openai'
    );

    // Verifica se a integração existe e está habilitada
    isConnected.value = openaiIntegration?.enabled || false;

    // Se estiver conectado e tiver hooks configurados, pega a API key
    if (isConnected.value && openaiIntegration?.hooks?.[0]?.settings?.api_key) {
      apiKey.value = openaiIntegration.hooks[0].settings.api_key;
    }
  } catch (error) {
    console.error('Erro ao verificar integração:', error);
    isConnected.value = false;
  }
});

const handleSave = () => {
  console.log('Salvando configurações:', {
    apiKey: apiKey.value,
    model: selectedModel.value,
  });
  emit('close');
};
</script>

<style lang="scss" scoped>
.modal-backdrop {
  @apply fixed inset-0 bg-slate-900 bg-opacity-30 flex items-center justify-center z-50;
}

.modal {
  @apply bg-white dark:bg-slate-800 rounded-xl shadow-lg w-full max-w-md mx-4;
}

.modal-header {
  @apply flex items-center justify-between p-4 border-b dark:border-slate-700;
  h3 {
    @apply text-lg font-medium;
  }
}

.modal-body {
  @apply p-4;
}

.modal-footer {
  @apply flex justify-end p-4 border-t dark:border-slate-700;
}

.btn-close {
  @apply text-slate-500 hover:text-slate-700 dark:text-slate-400 
    dark:hover:text-slate-300 text-xl font-bold;
}

.btn-save {
  @apply px-4 py-2 bg-woot-500 text-white rounded-lg 
    hover:bg-woot-600 transition-colors;
}

.modal-fade-enter-active,
.modal-fade-leave-active {
  transition: opacity 0.3s ease;
}

.modal-fade-enter-from,
.modal-fade-leave-to {
  opacity: 0;
}
</style>
