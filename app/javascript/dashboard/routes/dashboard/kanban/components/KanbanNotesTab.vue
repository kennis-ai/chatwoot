<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import FileUpload from 'vue-upload-component';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import {
  MAXIMUM_FILE_UPLOAD_SIZE,
  ALLOWED_FILE_TYPES,
} from 'shared/constants/messages';
import { emitter } from 'shared/helpers/mitt';
import Modal from 'dashboard/components/Modal.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import KanbanAPI from 'dashboard/api/kanban';
import MarkdownIt from 'markdown-it';

// Props
const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  notes: {
    type: Array,
    required: true,
  },
  isStacklab: {
    type: Boolean,
    default: false,
  },
  kanbanItems: {
    type: Array,
    default: () => [],
  },
  conversations: {
    type: Array,
    default: () => [],
  },
  contactsList: {
    type: Array,
    default: () => [],
  },
  loadingItems: {
    type: Boolean,
    default: false,
  },
  loadingConversations: {
    type: Boolean,
    default: false,
  },
  loadingContacts: {
    type: Boolean,
    default: false,
  },
  currentUser: {
    type: Object,
    required: true,
  },
});

// Emits
const emit = defineEmits([
  'update:item',
  'item-updated',
  'upload-attachment',
  'delete-attachment',
]);

const { t } = useI18n();

// Instância do MarkdownIt com configurações padrão
const md = new MarkdownIt({
  html: false, // Desabilitar HTML inline para segurança
  breaks: true, // Converter quebras de linha em <br>
  linkify: true, // Converter URLs em links automaticamente
});

// Função para renderizar markdown
const renderMarkdown = text => {
  if (!text) return '';

  // Renderizar diretamente - markdown-it já suporta listas por padrão
  return md.render(text);
};

// Refs para o componente
const currentNote = ref('');
const savingNotes = ref(false);
const editingNoteId = ref(null);
const editingNoteContent = ref('');
const noteAttachments = ref([]);
const isUploadingAttachment = ref(false);
const selectedFileName = ref('');
const loadingNotes = ref(false);
const internalNotes = ref([]);

// Refs para dropdown de vinculação
const showLinkDropdown = ref(false);

// Refs para vinculação
const showItemSelector = ref(false);
const showConversationSelector = ref(false);
const showContactSelector = ref(false);
const selectedItemId = ref(null);
const selectedConversationId = ref(null);
const selectedContactId = ref(null);

// Computed properties
const selectedLinksPreview = computed(() => {
  const links = [];
  if (selectedItemId.value) {
    links.push({ type: 'item', id: selectedItemId.value });
  }
  if (selectedConversationId.value) {
    links.push({ type: 'conversation', id: selectedConversationId.value });
  }
  if (selectedContactId.value) {
    links.push({ type: 'contact', id: selectedContactId.value });
  }
  return links;
});

const itemButtonText = computed(() => {
  if (showItemSelector.value) {
    return t('KANBAN.CANCEL');
  }

  if (selectedItemId.value) {
    const selectedItem = props.kanbanItems.find(
      item => item.id === selectedItemId.value
    );
    return selectedItem?.title || t('KANBAN.FORM.NOTES.LINK_ITEM');
  }

  return t('KANBAN.FORM.NOTES.LINK_ITEM');
});

const conversationButtonText = computed(() => {
  if (showConversationSelector.value) {
    return t('KANBAN.CANCEL');
  }

  if (selectedConversationId.value) {
    const selectedConversation = props.conversations.find(
      conv => conv.id === selectedConversationId.value
    );
    return selectedConversation
      ? `#${selectedConversation.id} - ${selectedConversation.title}`
      : t('KANBAN.FORM.NOTES.LINK_CONVERSATION');
  }

  return t('KANBAN.FORM.NOTES.LINK_CONVERSATION');
});

const contactButtonText = computed(() => {
  if (showContactSelector.value) {
    return t('KANBAN.CANCEL');
  }

  if (selectedContactId.value) {
    const selectedContact = props.contactsList.find(
      contact => contact.id === selectedContactId.value
    );
    return selectedContact?.name || t('KANBAN.FORM.NOTES.LINK_CONTACT');
  }

  return t('KANBAN.FORM.NOTES.LINK_CONTACT');
});

// Funções utilitárias
const isImage = attachment => {
  try {
    return !!(
      attachment &&
      typeof attachment === 'object' &&
      attachment.fileType &&
      typeof attachment.fileType === 'string' &&
      attachment.fileType.startsWith('image/')
    );
  } catch (error) {
    return false;
  }
};

const hasNonImageAttachments = note => {
  return note.attachments?.some(a => !isImage(a)) || false;
};

const hasImageAttachments = note => {
  return note.attachments?.some(isImage) || false;
};

const getNonImageAttachments = note => {
  return note.attachments?.filter(a => !isImage(a)) || [];
};

const getImageAttachments = note => {
  return note.attachments?.filter(isImage) || [];
};

const getFileIcon = attachment => {
  if (!attachment || !attachment.fileType) return '📎';
  return attachment.fileType.includes('pdf') ? '📄' : '📎';
};

const formatDate = date => {
  if (!date) return '';
  try {
    return new Date(date).toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch (error) {
    console.error('Erro ao formatar data:', error);
    return '';
  }
};

// Funções para manipulação de notas
const handleAddNote = async () => {
  if (
    !currentNote.value.trim() &&
    !noteAttachments.value?.length &&
    !selectedItemId.value &&
    !selectedConversationId.value &&
    !selectedContactId.value
  )
    return;

  try {
    const noteData = {
      text: currentNote.value,
      attachments: noteAttachments.value,
      linked_item_id: selectedItemId.value,
      linked_conversation_id: selectedConversationId.value,
      linked_contact_id: selectedContactId.value,
    };

    await KanbanAPI.createNote(props.item.id, noteData);

    // Buscar notas atualizadas
    await fetchNotes();

    // Limpar estado
    currentNote.value = '';
    noteAttachments.value = [];
    selectedFileName.value = '';
    selectedItemId.value = null;
    selectedConversationId.value = null;
    selectedContactId.value = null;
    editingNoteId.value = null;

    // Mostrar mensagem de sucesso
    emitter.emit('newToastMessage', {
      message: t('KANBAN.NOTES.CREATED_SUCCESSFULLY'),
      action: { type: 'success' },
    });
  } catch (error) {
    console.error('Erro ao criar nota:', error);
    emitter.emit('newToastMessage', {
      message: t('KANBAN.NOTES.CREATE_ERROR'),
      action: { type: 'error' },
    });
  }
};

const handleEditNote = note => {
  editingNoteId.value = note.id;
  currentNote.value = note.text;
  selectedItemId.value = note.linked_item_id || null;
  selectedConversationId.value = note.linked_conversation_id || null;
  selectedContactId.value = note.linked_contact_id || null;
  noteAttachments.value = note.attachments || [];
};

const handleDeleteNote = async noteId => {
  try {
    await KanbanAPI.deleteNote(props.item.id, noteId);

    // Buscar notas atualizadas
    await fetchNotes();

    // Mostrar mensagem de sucesso
    emitter.emit('newToastMessage', {
      message: t('KANBAN.NOTES.DELETED_SUCCESSFULLY'),
      action: { type: 'success' },
    });
  } catch (error) {
    console.error('Erro ao deletar nota:', error);
    emitter.emit('newToastMessage', {
      message: t('KANBAN.NOTES.DELETE_ERROR'),
      action: { type: 'error' },
    });
  }
};

// Função para fechar dropdown após upload de arquivo
const closeDropdownAfterUpload = () => {
  showLinkDropdown.value = false;
};

const cancelEditNote = () => {
  editingNoteId.value = null;
  currentNote.value = '';
  noteAttachments.value = [];
  selectedFileName.value = '';
  selectedItemId.value = null;
  selectedConversationId.value = null;
  selectedContactId.value = null;
  showItemSelector.value = false;
  showConversationSelector.value = false;
  showContactSelector.value = false;
  showLinkDropdown.value = false;
};

// Funções para upload de anexos
const handleNoteAttachment = async file => {
  if (!file) return;

  selectedFileName.value = file.file.name;
  closeDropdownAfterUpload(); // Fecha o dropdown quando iniciar upload

  if (!props.item?.id) {
    console.error('ID do item não encontrado:', props.item);
    return;
  }

  isUploadingAttachment.value = true;
  try {
    if (checkFileSizeLimit(file, MAXIMUM_FILE_UPLOAD_SIZE)) {
      emit('upload-attachment', {
        file,
        type: 'note',
        source: editingNoteId.value
          ? { type: 'note', id: editingNoteId.value }
          : null,
      });
    }
  } catch (error) {
    console.error('Erro ao fazer upload:', error.message);
  } finally {
    isUploadingAttachment.value = false;
  }
};

// Funções para dropdown de vinculação
const toggleLinkDropdown = () => {
  showLinkDropdown.value = !showLinkDropdown.value;
};

const selectLinkType = type => {
  showLinkDropdown.value = false;

  switch (type) {
    case 'item':
      toggleItemSelector();
      break;
    case 'conversation':
      toggleConversationSelector();
      break;
    case 'contact':
      toggleContactSelector();
      break;
  }
};

// Funções para seletores
const toggleItemSelector = () => {
  if (showItemSelector.value) {
    showItemSelector.value = false;
  } else {
    showItemSelector.value = true;
    showConversationSelector.value = false;
    showContactSelector.value = false;
  }
};

const toggleConversationSelector = () => {
  if (showConversationSelector.value) {
    showConversationSelector.value = false;
  } else {
    showConversationSelector.value = true;
    showItemSelector.value = false;
    showContactSelector.value = false;
  }
};

const toggleContactSelector = () => {
  if (showContactSelector.value) {
    showContactSelector.value = false;
  } else {
    showContactSelector.value = true;
    showItemSelector.value = false;
    showConversationSelector.value = false;
  }
};

// Funções para seleção de itens
const selectItem = item => {
  selectedItemId.value = item.id;
  showItemSelector.value = false;
};

const selectConversation = conversation => {
  selectedConversationId.value = conversation.id;
  showConversationSelector.value = false;
};

const selectContact = contact => {
  selectedContactId.value = contact.id;
  showContactSelector.value = false;
};

// Computed para filtrar listas
const filteredKanbanItems = computed(() => {
  if (!itemSearchTerm.value) return props.kanbanItems;
  return props.kanbanItems.filter(item =>
    (item.title || '')
      .toLowerCase()
      .includes(itemSearchTerm.value.toLowerCase())
  );
});

const filteredConversations = computed(() => {
  if (!conversationSearchTerm.value) return props.conversations;
  return props.conversations.filter(conv =>
    ((conv.title || '') + ' ' + (conv.description || ''))
      .toLowerCase()
      .includes(conversationSearchTerm.value.toLowerCase())
  );
});

const filteredContactsList = computed(() => {
  if (!contactSearchTerm.value) return props.contactsList;
  return props.contactsList.filter(contact =>
    (contact.name || '')
      .toLowerCase()
      .includes(contactSearchTerm.value.toLowerCase())
  );
});

// Refs para busca
const itemSearchTerm = ref('');
const conversationSearchTerm = ref('');
const contactSearchTerm = ref('');

// Ref para controle de ordenação
const sortOrder = ref('newest'); // 'newest', 'oldest'

// Computed para usar notas internas ou da prop
const displayNotes = computed(() => {
  // Priorizar notas internas, depois props.notes, garantir sempre um array
  let notes =
    Array.isArray(internalNotes.value) && internalNotes.value.length > 0
      ? internalNotes.value
      : Array.isArray(props.notes)
        ? props.notes
        : [];

  if (!notes || notes.length === 0) return [];

  // Ordenar notas baseado no critério selecionado
  return [...notes].sort((a, b) => {
    switch (sortOrder.value) {
      case 'oldest':
        return new Date(a.created_at || 0) - new Date(b.created_at || 0);
      case 'newest':
      default:
        return new Date(b.created_at || 0) - new Date(a.created_at || 0);
    }
  });
});

// Função para obter detalhes de item vinculado
const getLinkedItemDetails = itemId => {
  return props.kanbanItems.find(item => item.id === itemId);
};

// Função para remover anexo
const removeAttachment = attachment => {
  emit('delete-attachment', attachment);
};

// Função para buscar notas do item
const fetchNotes = async () => {
  try {
    loadingNotes.value = true;
    const { data } = await KanbanAPI.getNotes(props.item.id);
    internalNotes.value = Array.isArray(data.notes) ? data.notes : [];
  } catch (error) {
    console.error('Erro ao buscar notas:', error);
    emitter.emit('newToastMessage', {
      message: t('KANBAN.NOTES.FETCH_ERROR'),
      action: { type: 'error' },
    });
  } finally {
    loadingNotes.value = false;
  }
};

// Carregar notas quando o componente for montado
onMounted(() => {
  if (props.item?.id) {
    fetchNotes();
  }
});

// Função para alternar ordenação
const toggleSortOrder = () => {
  const sortOptions = ['newest', 'oldest'];
  const currentIndex = sortOptions.indexOf(sortOrder.value);
  const nextIndex = (currentIndex + 1) % sortOptions.length;
  sortOrder.value = sortOptions[nextIndex];
};

// Função para obter o texto da ordenação atual
const getSortOrderText = () => {
  switch (sortOrder.value) {
    case 'newest':
      return t('KANBAN.NOTES.SORT_NEWEST');
    case 'oldest':
      return t('KANBAN.NOTES.SORT_OLDEST');
    default:
      return t('KANBAN.NOTES.SORT_NEWEST');
  }
};

// Função para abrir preview de imagem
const openImagePreview = url => {
  window.open(url, '_blank');
};
</script>

<template>
  <div class="space-y-4">
    <!-- Campo de texto para nova nota -->
    <div class="note-input-section">
      <Editor
        v-model="currentNote"
        :placeholder="t('KANBAN.FORM.NOTES.PLACEHOLDER')"
        :max-length="1000"
        :show-character-count="true"
        :enable-variables="false"
        :enable-canned-responses="false"
        :enable-captain-tools="false"
        :enabled-menu-options="[]"
      />

      <!-- Botões de ação -->
      <div class="flex items-center justify-between mt-2">
        <!-- Botão único de vinculação com dropdown -->
        <div v-if="isStacklab" class="relative">
          <!-- Botão principal de vinculação -->
          <button
            class="action-button hover:bg-slate-100 dark:hover:bg-slate-600"
            :class="{ 'bg-slate-100 dark:bg-slate-600': showLinkDropdown }"
            @click="toggleLinkDropdown"
          >
            <fluent-icon
              :icon="showLinkDropdown ? 'dismiss' : 'attach'"
              size="20"
            />
          </button>

          <!-- Dropdown de opções -->
          <div
            v-if="showLinkDropdown"
            class="link-dropdown absolute top-full mt-2 left-0 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg shadow-lg py-2 min-w-[180px] flex flex-col items-start"
          >
            <!-- Opção de upload de arquivo -->
            <FileUpload
              ref="upload"
              :accept="ALLOWED_FILE_TYPES"
              @input-file="handleNoteAttachment"
            >
              <button
                class="link-dropdown-item"
                :disabled="isUploadingAttachment"
              >
                <fluent-icon
                  icon="attach"
                  size="16"
                  class="text-slate-600 dark:text-slate-400"
                />
                <span>{{
                  isUploadingAttachment ? '...' : 'Anexar arquivo'
                }}</span>
              </button>
            </FileUpload>

            <!-- Separador -->
            <div class="border-t border-slate-200 dark:border-slate-700 my-1" />

            <!-- Opções de vinculação -->
            <button class="link-dropdown-item" @click="selectLinkType('item')">
              <fluent-icon
                icon="link"
                size="16"
                class="text-blue-600 dark:text-blue-400"
              />
              <span>{{ t('KANBAN.FORM.NOTES.LINK_ITEM') }}</span>
            </button>
            <button
              class="link-dropdown-item"
              @click="selectLinkType('conversation')"
            >
              <fluent-icon
                icon="chat"
                size="16"
                class="text-slate-600 dark:text-slate-400"
              />
              <span>{{ t('KANBAN.FORM.NOTES.LINK_CONVERSATION') }}</span>
            </button>
            <button
              class="link-dropdown-item"
              @click="selectLinkType('contact')"
            >
              <fluent-icon
                icon="person"
                size="16"
                class="text-purple-600 dark:text-purple-400"
              />
              <span>{{ t('KANBAN.FORM.NOTES.LINK_CONTACT') }}</span>
            </button>
          </div>
        </div>

        <!-- Botão de adicionar nota -->
        <button
          class="primary-button"
          :disabled="
            !currentNote.trim() &&
            !noteAttachments.length &&
            !selectedItemId &&
            !selectedConversationId &&
            !selectedContactId
          "
          @click="handleAddNote"
        >
          {{ editingNoteId ? t('SAVE') : t('KANBAN.ADD') }}
        </button>
      </div>

      <!-- Preview do arquivo selecionado -->
      <div
        v-if="selectedFileName"
        class="flex items-center gap-2 px-2 py-1 text-xs text-slate-600 dark:text-slate-400 mt-2"
      >
        <fluent-icon icon="document" size="12" />
        <span class="truncate">{{ selectedFileName }}</span>
      </div>

      <!-- Preview das seleções ativas -->
      <div
        v-if="selectedItemId || selectedConversationId || selectedContactId"
        class="selected-links-preview mt-2 mb-3 space-y-2"
      >
        <!-- Item selecionado -->
        <div v-if="selectedItemId" class="selected-link">
          <div
            class="flex items-center justify-between p-2 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800"
          >
            <div class="flex items-center gap-2">
              <fluent-icon
                icon="link"
                size="14"
                class="text-blue-600 dark:text-blue-400"
              />
              <span class="text-sm text-blue-700 dark:text-blue-300">
                {{
                  getLinkedItemDetails(selectedItemId)?.title ||
                  `Item #${selectedItemId}`
                }}
              </span>
            </div>
            <button
              class="p-1 text-blue-400 hover:text-blue-600 dark:hover:text-blue-300"
              @click="selectedItemId = null"
            >
              <fluent-icon icon="dismiss" size="12" />
            </button>
          </div>
        </div>

        <!-- Conversa selecionada -->
        <div v-if="selectedConversationId" class="selected-link">
          <div
            class="flex items-center justify-between p-2 bg-green-50 dark:bg-green-900/20 rounded-lg border border-green-200 dark:border-green-800"
          >
            <div class="flex items-center gap-2">
              <fluent-icon
                icon="chat"
                size="14"
                class="text-green-600 dark:text-green-400"
              />
              <span class="text-sm text-green-700 dark:text-green-300">
                Conversa #{{ selectedConversationId }}
              </span>
            </div>
            <button
              class="p-1 text-green-400 hover:text-green-600 dark:hover:text-green-300"
              @click="selectedConversationId = null"
            >
              <fluent-icon icon="dismiss" size="12" />
            </button>
          </div>
        </div>

        <!-- Contato selecionado -->
        <div v-if="selectedContactId" class="selected-link">
          <div
            class="flex items-center justify-between p-2 bg-purple-50 dark:bg-purple-900/20 rounded-lg border border-purple-200 dark:border-purple-800"
          >
            <div class="flex items-center gap-2">
              <fluent-icon
                icon="person"
                size="14"
                class="text-purple-600 dark:text-purple-400"
              />
              <span class="text-sm text-purple-700 dark:text-purple-300">
                {{
                  contactsList.find(c => c.id === selectedContactId)?.name ||
                  `Contato #${selectedContactId}`
                }}
              </span>
            </div>
            <button
              class="p-1 text-purple-400 hover:text-purple-600 dark:hover:text-purple-300"
              @click="selectedContactId = null"
            >
              <fluent-icon icon="dismiss" size="12" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Seletor de itens -->
    <Modal
      v-if="showItemSelector"
      :show="showItemSelector"
      @close="showItemSelector = false"
    >
      <div class="item-selector p-0 bg-transparent border-none shadow-none">
        <div class="px-4 py-3 border-b border-slate-200 dark:border-slate-700">
          <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300">
            {{ t('KANBAN.FORM.NOTES.SELECT_ITEM') }}
          </h4>
        </div>
        <!-- Caixa de busca -->
        <div class="px-4 py-2">
          <input
            v-model="itemSearchTerm"
            type="text"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg focus:ring-1 focus:ring-woot-500 focus:border-woot-500 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300"
            placeholder="Buscar..."
          />
        </div>
        <div class="max-h-[280px] overflow-y-auto custom-scrollbar">
          <div
            v-if="loadingItems"
            class="p-4 text-center text-sm text-slate-500"
          >
            <span class="loading-spinner w-4 h-4 mr-2" />
            {{ t('KANBAN.LOADING') }}
          </div>
          <div
            v-else-if="filteredKanbanItems.length === 0"
            class="p-4 text-center"
          >
            <p class="text-sm text-slate-500">
              {{ t('KANBAN.FORM.NOTES.NO_ITEMS') }}
            </p>
          </div>
          <div v-else class="divide-y divide-slate-100 dark:divide-slate-700">
            <button
              v-for="item in filteredKanbanItems"
              :key="item.id"
              class="w-full px-4 py-3 text-left hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors focus:outline-none focus:bg-slate-50 dark:focus:bg-slate-700"
              @click="selectItem(item)"
            >
              <div class="flex items-center gap-3">
                <!-- Prioridade -->
                <div
                  class="flex-shrink-0 w-1.5 h-5 rounded-full"
                  :class="{
                    'bg-n-ruby-9': item.priority === 'high',
                    'bg-yellow-500': item.priority === 'medium',
                    'bg-green-500': item.priority === 'low',
                    'bg-slate-300': item.priority === 'none',
                  }"
                />
                <div class="flex items-center gap-3 flex-1 min-w-0">
                  <h4
                    class="text-sm font-medium text-slate-900 dark:text-slate-100 truncate flex-1"
                  >
                    {{ item.title }}
                  </h4>
                  <span
                    class="px-2 py-0.5 text-xs font-medium rounded-full bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 whitespace-nowrap"
                  >
                    {{ item.stage_name }}
                  </span>
                  <span
                    class="flex items-center gap-1 text-xs text-slate-400 whitespace-nowrap"
                  >
                    <fluent-icon icon="calendar" size="12" />
                    {{ item.createdAt }}
                  </span>
                </div>
              </div>
              <p
                v-if="item.description"
                class="mt-1 ml-6 text-xs text-slate-500 dark:text-slate-400 line-clamp-1"
              >
                {{ item.description }}
              </p>
            </button>
          </div>
        </div>
      </div>
    </Modal>

    <!-- Seletor de conversas -->
    <Modal
      v-if="showConversationSelector"
      :show="showConversationSelector"
      @close="showConversationSelector = false"
    >
      <div
        class="conversation-selector p-0 bg-transparent border-none shadow-none"
      >
        <div class="px-4 py-3 border-b border-slate-200 dark:border-slate-700">
          <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300">
            {{ t('KANBAN.FORM.NOTES.SELECT_CONVERSATION') }}
          </h4>
        </div>
        <!-- Caixa de busca -->
        <div class="px-4 py-2">
          <input
            v-model="conversationSearchTerm"
            type="text"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg focus:ring-1 focus:ring-woot-500 focus:border-woot-500 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300"
            placeholder="Buscar..."
          />
        </div>
        <div class="max-h-[280px] overflow-y-auto custom-scrollbar">
          <div
            v-if="loadingConversations"
            class="p-4 text-center text-sm text-slate-500"
          >
            <span class="loading-spinner w-4 h-4 mr-2" />
            {{ t('KANBAN.LOADING') }}
          </div>
          <div
            v-else-if="filteredConversations.length === 0"
            class="p-4 text-center"
          >
            <p class="text-sm text-slate-500">
              {{ t('KANBAN.FORM.NOTES.NO_CONVERSATIONS') }}
            </p>
          </div>
          <div v-else class="divide-y divide-slate-100 dark:divide-slate-700">
            <button
              v-for="conversation in filteredConversations"
              :key="conversation.id"
              class="w-full px-4 py-3 text-left hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors focus:outline-none focus:bg-slate-50 dark:focus:bg-slate-700"
              @click="selectConversation(conversation)"
            >
              <div class="flex items-center gap-3">
                <div
                  class="flex-shrink-0 w-1.5 h-5 rounded-full"
                  :class="{
                    'bg-green-500': conversation.status === 'open',
                    'bg-yellow-500': conversation.status === 'pending',
                    'bg-slate-500': conversation.status === 'resolved',
                  }"
                />
                <div class="flex items-center gap-3 flex-1 min-w-0">
                  <h4
                    class="text-sm font-medium text-slate-900 dark:text-slate-100 truncate flex-1"
                  >
                    #{{ conversation.id }} - {{ conversation.title }}
                  </h4>
                  <span
                    class="px-2 py-0.5 text-xs font-medium rounded-full bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 whitespace-nowrap"
                  >
                    {{ conversation.channel_type }}
                  </span>
                  <span
                    class="flex items-center gap-1 text-xs text-slate-400 whitespace-nowrap"
                  >
                    <fluent-icon icon="contact-card" size="12" />
                    {{ conversation.created_at }}
                  </span>
                </div>
              </div>
              <p
                v-if="conversation.description"
                class="mt-1 ml-6 text-xs text-slate-500 dark:text-slate-400 line-clamp-1"
              >
                {{ conversation.description }}
              </p>
            </button>
          </div>
        </div>
      </div>
    </Modal>

    <!-- Seletor de contatos -->
    <Modal
      v-if="showContactSelector"
      :show="showContactSelector"
      @close="showContactSelector = false"
    >
      <div class="contact-selector p-0 bg-transparent border-none shadow-none">
        <div class="px-4 py-3 border-b border-slate-200 dark:border-slate-700">
          <h4 class="text-sm font-medium text-slate-700 dark:text-slate-300">
            {{ t('KANBAN.FORM.NOTES.SELECT_CONTACT') }}
          </h4>
        </div>
        <!-- Caixa de busca -->
        <div class="px-4 py-2">
          <input
            v-model="contactSearchTerm"
            type="text"
            class="w-full px-3 py-2 text-sm border border-slate-200 rounded-lg focus:ring-1 focus:ring-woot-500 focus:border-woot-500 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-300"
            placeholder="Buscar..."
          />
        </div>
        <div class="max-h-[280px] overflow-y-auto custom-scrollbar">
          <div
            v-if="loadingContacts"
            class="p-4 text-center text-sm text-slate-500"
          >
            <span class="loading-spinner w-4 h-4 mr-2" />
            {{ t('KANBAN.LOADING') }}
          </div>
          <div
            v-else-if="filteredContactsList.length === 0"
            class="p-4 text-center"
          >
            <p class="text-sm text-slate-500">
              {{ t('KANBAN.FORM.NOTES.NO_CONTACTS') }}
            </p>
          </div>
          <div v-else class="divide-y divide-slate-100 dark:divide-slate-700">
            <button
              v-for="contact in filteredContactsList"
              :key="contact.id"
              class="w-full px-4 py-3 text-left hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors focus:outline-none focus:bg-slate-50 dark:focus:bg-slate-700"
              @click="selectContact(contact)"
            >
              <div class="flex items-center gap-3">
                <Avatar
                  v-if="contact.avatar_url"
                  :src="contact.avatar_url"
                  :name="contact.name"
                  :size="24"
                />
                <div class="flex items-center gap-2">
                  <h3
                    class="text-sm font-medium text-slate-900 dark:text-slate-100"
                  >
                    {{ contact.name }}
                  </h3>
                </div>
              </div>
              <div
                v-if="contact.phone || contact.last_activity_at"
                class="mt-1 ml-9 flex items-center gap-4 text-xs text-slate-500"
              >
                <span v-if="contact.phone" class="flex items-center gap-1">
                  <fluent-icon icon="call" size="12" />
                  {{ contact.phone }}
                </span>
                <span
                  v-if="contact.last_activity_at"
                  class="flex items-center gap-1"
                >
                  <fluent-icon icon="alarm" size="12" />
                  {{ t('KANBAN.FORM.NOTES.LAST_ACTIVITY') }}:
                  {{ contact.last_activity_at }}
                </span>
              </div>
            </button>
          </div>
        </div>
      </div>
    </Modal>

    <!-- Seção de notas -->
    <div class="notes-section pb-8">
      <!-- Botão de ordenação -->
      <div class="flex justify-between items-center mb-4">
        <h3 class="text-lg font-medium text-slate-900 dark:text-slate-100">
          {{ t('KANBAN.NOTES.TITLE') }}
        </h3>
        <button
          v-if="displayNotes.length > 1"
          class="sort-button"
          :title="getSortOrderText()"
          @click="toggleSortOrder"
        >
          <fluent-icon icon="arrow-sort" size="16" />
          <span class="ml-1">{{ getSortOrderText() }}</span>
        </button>
      </div>

      <!-- Lista de notas -->
      <div v-for="note in displayNotes" :key="note.id" class="note-card">
        <div class="note-layout">
          <div class="note-content">
            <div class="flex items-start justify-between">
              <div class="note-text" v-html="renderMarkdown(note.text)" />
              <!-- Botões de ação -->
              <div class="flex items-center gap-1">
                <button
                  class="p-1 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
                  @click="handleEditNote(note)"
                >
                  <span class="icon-button">
                    <fluent-icon icon="edit" size="16" />
                  </span>
                </button>
                <button
                  class="p-1 text-slate-400 hover:text-n-ruby-9 dark:hover:text-n-ruby-4"
                  @click="handleDeleteNote(note.id)"
                >
                  <span class="icon-button">
                    <fluent-icon icon="delete" size="16" />
                  </span>
                </button>
              </div>
            </div>

            <!-- Vinculações da nota -->
            <div
              v-if="
                note.linked_item_id ||
                note.linked_conversation_id ||
                note.linked_contact_id
              "
              class="note-links mt-3 mb-3"
            >
              <!-- Item vinculado -->
              <div v-if="note.linked_item_id" class="linked-item">
                <div
                  class="flex items-center gap-2 p-2 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800"
                >
                  <fluent-icon
                    icon="link"
                    size="14"
                    class="text-blue-600 dark:text-blue-400"
                  />
                  <span class="text-sm text-blue-700 dark:text-blue-300">
                    {{ t('KANBAN.FORM.NOTES.LINKED_ITEM') }}:
                    {{
                      getLinkedItemDetails(note.linked_item_id)?.title ||
                      `#${note.linked_item_id}`
                    }}
                  </span>
                </div>
              </div>

              <!-- Conversa vinculada -->
              <div
                v-if="note.linked_conversation_id"
                class="linked-conversation mt-2"
              >
                <div
                  class="flex items-center gap-2 p-2 bg-green-50 dark:bg-green-900/20 rounded-lg border border-green-200 dark:border-green-800"
                >
                  <fluent-icon
                    icon="chat"
                    size="14"
                    class="text-green-600 dark:text-green-400"
                  />
                  <span class="text-sm text-green-700 dark:text-green-300">
                    {{ t('KANBAN.FORM.NOTES.LINKED_CONVERSATION') }}: #{{
                      note.linked_conversation_id
                    }}
                  </span>
                </div>
              </div>

              <!-- Contato vinculado -->
              <div v-if="note.linked_contact_id" class="linked-contact mt-2">
                <div
                  class="flex items-center gap-2 p-2 bg-purple-50 dark:bg-purple-900/20 rounded-lg border border-purple-200 dark:border-purple-800"
                >
                  <fluent-icon
                    icon="person"
                    size="14"
                    class="text-purple-600 dark:text-purple-400"
                  />
                  <span class="text-sm text-purple-700 dark:text-purple-300">
                    {{ t('KANBAN.FORM.NOTES.LINKED_CONTACT') }}:
                    {{
                      contactsList?.find?.(c => c.id === note.linked_contact_id)
                        ?.name || `#${note.linked_contact_id}`
                    }}
                  </span>
                </div>
              </div>
            </div>

            <!-- Metadados da nota -->
            <div class="note-metadata">
              <div class="flex items-center gap-2">
                <Avatar
                  :name="note.author"
                  :src="note.author_avatar"
                  :size="20"
                />
                <span class="note-author">{{ note.author }}</span>
              </div>
              <span class="note-date">
                {{ formatDate(note.created_at || new Date()) }}
              </span>
            </div>

            <!-- Arquivos não-imagem -->
            <div v-if="hasNonImageAttachments(note)" class="note-files">
              <div
                v-for="attachment in getNonImageAttachments(note)"
                :key="attachment.id"
                class="file-attachment"
              >
                <div class="file-info">
                  <span class="file-icon">
                    {{ getFileIcon(attachment) }}
                  </span>
                  <a
                    :href="attachment.url"
                    target="_blank"
                    class="file-name"
                    :title="attachment.filename"
                  >
                    {{ attachment.filename }}
                  </a>
                </div>
                <button
                  class="file-action"
                  @click="removeAttachment(attachment)"
                >
                  <fluent-icon icon="delete" size="12" />
                </button>
              </div>
            </div>
          </div>

          <!-- Preview de imagens -->
          <div v-if="hasImageAttachments(note)" class="note-images">
            <div
              v-for="attachment in getImageAttachments(note)"
              :key="attachment.id"
              class="image-preview"
            >
              <img
                :src="attachment.url"
                :alt="attachment.filename"
                class="preview-image"
                @click="openImagePreview(attachment.url)"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Estilos específicos do componente NotesTab */
.note-input-section {
  @apply space-y-2;
}

.action-button {
  @apply flex items-center justify-center w-10 h-10 rounded-lg
         text-slate-600 hover:text-slate-900
         dark:text-slate-400 dark:hover:text-slate-200
         bg-slate-50 hover:bg-slate-100
         dark:bg-slate-700 dark:hover:bg-slate-600
         transition-all duration-200;

  &:disabled {
    @apply opacity-50 cursor-not-allowed;
  }
}

.primary-button {
  @apply px-4 py-2 text-sm font-medium text-white
         bg-woot-500 hover:bg-woot-600
         dark:bg-woot-600 dark:hover:bg-woot-700
         rounded-lg transition-colors;

  &:disabled {
    @apply opacity-50 cursor-not-allowed;
  }
}

.notes-section {
  @apply flex flex-col gap-4;
}

.note-card {
  @apply bg-white dark:bg-slate-800 rounded-lg p-4 mb-4
         border border-slate-200 dark:border-slate-700;
}

.note-layout {
  @apply flex justify-between gap-4;
}

.note-content {
  @apply flex-1 flex flex-col justify-between;
}

.note-text {
  @apply flex-1 text-slate-700 dark:text-slate-300 whitespace-pre-wrap break-words overflow-hidden mb-4;
}

.note-metadata {
  @apply flex items-center justify-between text-sm
         text-slate-500 dark:text-slate-400 mb-3;
}

.note-author {
  @apply font-medium;
}

.note-date {
  @apply text-xs;
}

.note-files {
  @apply mt-4 space-y-2 border-t border-slate-100 dark:border-slate-700 pt-4;
}

.file-attachment {
  @apply flex items-center justify-between p-2
         bg-slate-50 dark:bg-slate-700
         rounded-lg text-sm;
}

.file-info {
  @apply flex items-center gap-1.5 flex-1 min-w-0;
}

.file-icon {
  @apply flex-shrink-0 text-slate-400;
}

.file-name {
  @apply text-[10px] hover:text-woot-500 dark:hover:text-woot-400
         text-slate-700 dark:text-slate-300 max-w-[150px]
         whitespace-nowrap;
}

.file-action {
  @apply p-1.5 text-slate-400 hover:text-n-ruby-9
           dark:text-slate-500 dark:hover:text-n-ruby-4
         rounded-md hover:bg-slate-100 dark:hover:bg-slate-600
         transition-colors;
}

.note-images {
  @apply flex-shrink-0 flex flex-col gap-3 w-24;
}

.image-preview {
  @apply rounded-lg overflow-hidden bg-slate-50 dark:bg-slate-700;
}

.preview-image {
  @apply w-24 h-24 object-cover rounded-lg cursor-pointer
         hover:opacity-90 transition-opacity;
}

/* Quando não há imagens, o conteúdo ocupa todo o espaço */
.note-layout:not(:has(.note-images)) .note-content {
  @apply w-full;
}

/* Ajuste para telas menores */
@media (max-width: 640px) {
  .note-layout {
    @apply flex-col gap-3;
  }

  .note-images {
    @apply w-full flex-row flex-wrap;
  }

  .preview-image {
    @apply w-16 h-16;
  }
}

/* Estilos adicionais para os botões de ação */
.note-actions {
  @apply flex items-center gap-1;
}

.note-action-button {
  @apply p-1 text-slate-400 transition-colors;
}

.note-action-button:hover {
  @apply text-slate-600 dark:text-slate-300;
}

.note-action-button.delete:hover {
  @apply text-n-ruby-9 dark:text-n-ruby-4;
}

.icon-button {
  @apply flex items-center justify-center w-6 h-6 rounded-full
         transition-colors duration-200;
}

.icon-button:hover {
  @apply bg-slate-100 dark:bg-slate-700;
}

.selected-links-preview {
  @apply border-t border-slate-200 dark:border-slate-700 pt-3;
}

.selected-link {
  @apply transition-all duration-200;
}

/* Estilos para vinculações de notas */
.note-links {
  @apply space-y-2;
}

.linked-item,
.linked-conversation,
.linked-contact {
  @apply transition-all duration-200;
}

.custom-scrollbar {
  scrollbar-width: thin;
  scrollbar-color: var(--color-scrollbar) transparent;
}

.custom-scrollbar::-webkit-scrollbar {
  width: 6px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: transparent;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background-color: var(--color-scrollbar);
  border-radius: 3px;
}

.dark .custom-scrollbar {
  scrollbar-color: var(--color-scrollbar-dark) transparent;
}

.dark .custom-scrollbar::-webkit-scrollbar-thumb {
  background-color: var(--color-scrollbar-dark);
}

/* Dropdown de vinculação */
.link-dropdown {
  @apply z-50;
}

.link-dropdown-item {
  @apply flex items-center gap-3 px-4 py-2 text-sm text-slate-700 dark:text-slate-300
         hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors w-full text-left;
}

.link-dropdown-item:hover .fluent-icon {
  @apply opacity-80;
}

.link-dropdown-item:disabled {
  @apply opacity-60 cursor-not-allowed;
}

.link-dropdown-item:disabled:hover {
  @apply bg-transparent dark:bg-transparent;
}

/* Botão de ordenação */
.sort-button {
  @apply flex items-center px-3 py-1.5 text-sm font-medium
         text-slate-600 dark:text-slate-400
         bg-slate-100 hover:bg-slate-200
         dark:bg-slate-700 dark:hover:bg-slate-600
         rounded-lg transition-colors duration-200
         border border-slate-200 dark:border-slate-600;
}

.sort-button:hover {
  @apply text-slate-900 dark:text-slate-200;
}
</style>
