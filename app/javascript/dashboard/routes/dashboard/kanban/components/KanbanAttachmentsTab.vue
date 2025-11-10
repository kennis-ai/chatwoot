<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import FileUpload from 'vue-upload-component';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import {
  MAXIMUM_FILE_UPLOAD_SIZE,
  ALLOWED_FILE_TYPES,
} from 'shared/constants/messages';
import KanbanAPI from '../../../../api/kanban';

// Props
const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  isStacklab: {
    type: Boolean,
    default: false,
  },
});

// Emits
const emit = defineEmits([
  'upload-attachment',
  'delete-attachment'
]);

const { t } = useI18n();

// Refs para o componente
const isUploadingAttachment = ref(false);
const showFormatsPopover = ref(false);
const internalAttachments = ref([]);
const loadingAttachments = ref(false);

// Computed properties
const displayAttachments = computed(() => {
  // Usar attachments internos se disponíveis, senão usar da prop
  let attachments = internalAttachments.value.length > 0 ? internalAttachments.value : (props.item?.attachments || []);

  // Ensure attachments is an array before calling map
  if (!Array.isArray(attachments)) {
    return [];
  }

  return attachments.map(attachment => ({
    id: attachment.id,
    url: attachment.url,
    filename: attachment.filename,
    fileType: attachment.content_type,
    byteSize: attachment.byte_size,
    createdAt: attachment.created_at,
    source: {
      type: 'item',
      id: props.item?.id,
    },
  }));
});

const getAllAttachments = displayAttachments;

// Função para buscar attachments do item
const fetchAttachments = async () => {
  try {
    loadingAttachments.value = true;
    const { data } = await KanbanAPI.getAttachments(props.item.id);
    internalAttachments.value = data.attachments || [];
  } catch (error) {
    console.error('Erro ao buscar attachments:', error);
  } finally {
    loadingAttachments.value = false;
  }
};

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

const hasNonImageAttachments = computed(() => {
  return getAllAttachments.value.some(a => !isImage(a)) || false;
});

const hasImageAttachments = computed(() => {
  return getAllAttachments.value.some(isImage) || false;
});

const getNonImageAttachments = computed(() => {
  return getAllAttachments.value.filter(a => !isImage(a)) || [];
});

const getImageAttachments = computed(() => {
  return getAllAttachments.value.filter(isImage) || [];
});

// Computed para filtrar PDFs
const getPdfAttachments = computed(() => {
  return getAllAttachments.value.filter(attachment =>
    attachment.fileType === 'application/pdf'
  ) || [];
});

// Computed para filtrar outros documentos (excluindo PDFs)
const getDocumentAttachments = computed(() => {
  return getAllAttachments.value.filter(attachment =>
    !isImage(attachment) &&
    attachment.fileType !== 'application/pdf' &&
    (
      attachment.fileType?.startsWith('application/') ||
      attachment.fileType?.startsWith('text/')
    )
  ) || [];
});

// Computed para contar anexos por tipo
const imageAttachmentsCount = computed(() => {
  return getImageAttachments.value.length;
});

const pdfAttachmentsCount = computed(() => {
  return getPdfAttachments.value.length;
});

const documentAttachmentsCount = computed(() => {
  return getDocumentAttachments.value.length;
});

const nonImageAttachmentsCount = computed(() => {
  return getNonImageAttachments.value.length;
});

const getFileIcon = attachment => {
  if (!attachment || !attachment.fileType) return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-paperclip-icon lucide-paperclip"><path d="m16 6-8.414 8.586a2 2 0 0 0 2.829 2.829l8.414-8.586a4 4 0 1 0-5.657-5.657l-8.379 8.551a6 6 0 1 0 8.485 8.485l8.379-8.551"/></svg>';
  if (attachment.fileType.includes('pdf')) return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-file-text-icon lucide-file-text"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>';
  if (attachment.fileType.includes('doc')) return '📝';
  if (attachment.fileType.includes('xls') || attachment.fileType.includes('spreadsheet')) return '📊';
  if (attachment.fileType.includes('ppt') || attachment.fileType.includes('presentation')) return '📽️';
  if (attachment.fileType.includes('zip') || attachment.fileType.includes('rar')) return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-file-archive-icon lucide-file-archive"><path d="M10 12v-1"/><path d="M10 18v-2"/><path d="M10 7V6"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M15.5 22H18a2 2 0 0 0 2-2V7l-5-5H6a2 2 0 0 0-2 2v16a2 2 0 0 0 .274 1.01"/><circle cx="10" cy="20" r="2"/></svg>';
  return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-paperclip-icon lucide-paperclip"><path d="m16 6-8.414 8.586a2 2 0 0 0 2.829 2.829l8.414-8.586a4 4 0 1 0-5.657-5.657l-8.379 8.551a6 6 0 1 0 8.485 8.485l8.379-8.551"/></svg>';
};

// Função para formatar tamanho do arquivo
const formatFileSize = bytes => {
  if (!bytes || bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
};

// Função para formatar data
const formatDate = dateString => {
  if (!dateString) return '';
  const date = new Date(dateString);
  return date.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
};

// Função para fazer upload de anexo
const handleItemAttachment = async file => {
  if (!file) return;

  if (!props.item?.id) {
    console.error('ID do item não encontrado:', props.item);
    return;
  }

  isUploadingAttachment.value = true;
  try {
    if (checkFileSizeLimit(file, MAXIMUM_FILE_UPLOAD_SIZE)) {
      // Usar o método da API do kanban
      const response = await KanbanAPI.uploadAttachment(props.item?.id, file.file);

      // Buscar attachments atualizados para manter reatividade
      await fetchAttachments();
    }
  } catch (error) {
    console.error('Erro ao fazer upload:', error.message);
  } finally {
    isUploadingAttachment.value = false;
  }
};

// Função para remover anexo
const removeAttachment = async attachment => {
  const isItemAttachment = attachment.source.type === 'item';

  if (isItemAttachment) {
    try {
      // Usar o método da API do kanban
      await KanbanAPI.deleteAttachment(props.item?.id, attachment.id);

      // Buscar attachments atualizados para manter reatividade
      await fetchAttachments();
    } catch (error) {
      console.error('Erro ao remover anexo:', error.message);
    }
  } else {
    // Para anexos de notas, emitir evento para o componente pai
    emit('delete-attachment', attachment);
  }
};

// Função para abrir preview de imagem
const openImagePreview = url => {
  window.open(url, '_blank');
};



// Carregar attachments quando o componente for montado
onMounted(() => {
  if (props.item?.id) {
    fetchAttachments();
  }
});
</script>

<template>
  <div class="space-y-4">
    <!-- Botão de upload -->
    <div class="flex justify-between items-center">
      <div class="flex items-center gap-3">
        <FileUpload
          ref="uploadItem"
          :accept="ALLOWED_FILE_TYPES"
          @input-file="handleItemAttachment"
        >
          <button
            class="primary-button flex items-center gap-2"
            :disabled="isUploadingAttachment"
          >
            <fluent-icon icon="attach" size="16" />
            {{ t('KANBAN.ITEM_DETAILS.ATTACHMENTS.ADD_FILE') }}
            <span v-if="isUploadingAttachment">...</span>
          </button>
        </FileUpload>

        <!-- Ícone de informação com popover -->
        <div class="relative">
          <button
            class="info-icon-button"
            @mouseenter="showFormatsPopover = true"
            @mouseleave="showFormatsPopover = false"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10"/>
              <path d="M12 16v-4"/>
              <path d="M12 8h.01"/>
            </svg>
          </button>

          <!-- Popover com formatos aceitos -->
          <div
            v-if="showFormatsPopover"
            class="formats-popover"
          >
            <div class="popover-header">Formatos aceitos:</div>
            <div class="formats-list">
              <div class="format-category">
                <strong>Imagens:</strong> PNG, JPG, JPEG, GIF, WEBP, SVG, BMP, etc.
              </div>
              <div class="format-category">
                <strong>Áudio:</strong> MP3, WAV, OGG, AAC, etc.
              </div>
              <div class="format-category">
                <strong>Vídeo:</strong> MP4, AVI, MOV, WMV, etc.
              </div>
              <div class="format-category">
                <strong>PDF:</strong> Arquivos PDF
              </div>
              <div class="format-category">
                <strong>Documentos:</strong> DOC, DOCX, XLS, XLSX, PPT, PPTX, ODT
              </div>
              <div class="format-category">
                <strong>Texto:</strong> CSV, TXT, JSON, RTF, XML
              </div>
              <div class="format-category">
                <strong>Compactados:</strong> ZIP, 7Z, RAR, TAR
              </div>
              <div class="format-limit">
                Limite: 10MB por arquivo
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Contadores de anexos -->
      <div class="flex items-center gap-3 text-xs text-slate-500 dark:text-slate-400">
        <span
          v-if="imageAttachmentsCount > 0"
          class="flex items-center gap-1"
        >
          <fluent-icon icon="image" size="12" />
          {{ imageAttachmentsCount }}
        </span>
        <span
          v-if="pdfAttachmentsCount > 0"
          class="flex items-center gap-1"
        >
          <fluent-icon icon="document" size="12" />
          {{ pdfAttachmentsCount }}
        </span>
        <span
          v-if="documentAttachmentsCount > 0"
          class="flex items-center gap-1"
        >
          <fluent-icon icon="document" size="12" />
          {{ documentAttachmentsCount }}
        </span>
      </div>
    </div>

    <!-- Mensagem quando não há anexos -->
    <div
      v-if="getAllAttachments.length === 0"
      class="text-center py-8 text-slate-500 dark:text-slate-400"
    >
      {{ t('KANBAN.ITEM_DETAILS.ATTACHMENTS.EMPTY') }}
    </div>

    <!-- Lista de anexos -->
    <div
      v-else
      class="attachments-grid"
    >
      <!-- Seção de Imagens -->
      <div
        v-if="hasImageAttachments"
        class="attachment-section"
      >
        <h4 class="section-title">
          {{ t('KANBAN.ITEM_DETAILS.ATTACHMENTS.IMAGES') }}
        </h4>
        <div class="images-grid">
          <div
            v-for="attachment in getImageAttachments"
            :key="attachment.id"
            class="image-card"
          >
            <img
              :src="attachment.url"
              :alt="attachment.filename"
              class="attachment-preview"
              @click="() => openImagePreview(attachment.url)"
            />
            <div class="attachment-info">
              <div class="flex flex-col">
                <span class="attachment-name">{{
                  attachment.filename
                }}</span>
                <span class="attachment-meta">
                  {{ formatFileSize(attachment.byteSize) }} • {{ formatDate(attachment.createdAt) }}
                </span>
                <span class="attachment-source">
                  {{
                    attachment.source.type === 'note'
                      ? `Nota: ${attachment.source.text}`
                      : 'Anexo do item'
                  }}
                </span>
              </div>
              <button
                class="delete-button"
                @click="removeAttachment(attachment)"
              >
                <fluent-icon icon="delete" size="12" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Seção de PDFs -->
      <div
        v-if="getPdfAttachments.length > 0"
        class="attachment-section"
      >
        <h4 class="section-title">
          PDFs
        </h4>
        <div class="files-grid">
          <div
            v-for="attachment in getPdfAttachments"
            :key="attachment.id"
            class="file-card"
          >
            <div class="file-info">
              <span class="file-icon" v-html="getFileIcon(attachment)">
              </span>
              <div class="flex flex-col">
                <a
                  :href="attachment.url"
                  class="file-name"
                  :title="attachment.filename"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{ attachment.filename }}
                </a>
                <span class="file-meta">
                  {{ formatFileSize(attachment.byteSize) }} • {{ formatDate(attachment.createdAt) }}
                </span>
                <span class="file-source">
                  {{
                    attachment.source.type === 'note'
                      ? `Nota: ${attachment.source.text}`
                      : 'Anexo do item'
                  }}
                </span>
              </div>
            </div>
            <button
              class="delete-button"
              @click="removeAttachment(attachment)"
            >
              <fluent-icon icon="delete" size="12" />
            </button>
          </div>
        </div>
      </div>

      <!-- Seção de Documentos -->
      <div
        v-if="getDocumentAttachments.length > 0"
        class="attachment-section"
      >
        <h4 class="section-title">
          {{ t('KANBAN.ITEM_DETAILS.ATTACHMENTS.FILES') }}
        </h4>
        <div class="files-grid">
          <div
            v-for="attachment in getDocumentAttachments"
            :key="attachment.id"
            class="file-card"
          >
            <div class="file-info">
              <span class="file-icon" v-html="getFileIcon(attachment)">
              </span>
              <div class="flex flex-col">
                <a
                  :href="attachment.url"
                  target="_blank"
                  class="file-name"
                  :title="attachment.filename"
                >
                  {{ attachment.filename }}
                </a>
                <span class="file-meta">
                  {{ formatFileSize(attachment.byteSize) }} • {{ formatDate(attachment.createdAt) }}
                </span>
                <span class="file-source">
                  {{
                    attachment.source.type === 'note'
                      ? `Nota: ${attachment.source.text}`
                      : 'Anexo do item'
                  }}
                </span>
              </div>
            </div>
            <button
              class="delete-button"
              @click="removeAttachment(attachment)"
            >
              <fluent-icon icon="delete" size="12" />
            </button>
          </div>
        </div>
      </div>


      <!-- Mensagem quando não há anexos -->
      <div
        v-if="getAllAttachments.length === 0"
        class="text-center py-8 text-slate-500"
      >
        <fluent-icon icon="attach" size="48" class="mx-auto mb-4 opacity-50" />
        <p class="text-sm">{{ t('KANBAN.ITEM_DETAILS.ATTACHMENTS.EMPTY') }}</p>
      </div>
    </div>

  </div>
</template>

<style scoped>
.attachments-grid {
  @apply space-y-6;
}

.attachment-section {
  @apply space-y-3;
}

.section-title {
  @apply text-sm font-medium text-slate-700 dark:text-slate-300;
}

.images-grid {
  @apply grid grid-cols-8 gap-2;
}

.image-card {
  @apply rounded-md overflow-hidden bg-slate-50 dark:bg-slate-700
         border border-slate-200 dark:border-slate-600;
}

.attachment-preview {
  @apply w-full h-16 object-cover cursor-pointer
         hover:opacity-90 transition-opacity;
}

.attachment-info {
  @apply p-1 flex items-center justify-between;
}

.attachment-name {
  @apply text-[10px] text-slate-700 dark:text-slate-300 truncate max-w-[80px];
}

.attachment-source {
  @apply text-[8px] text-slate-500 dark:text-slate-400;
}

.attachment-meta {
  @apply text-[8px] text-slate-500 dark:text-slate-400 mt-0.5;
}

.files-grid {
  @apply space-y-2;
}

.file-card {
  @apply flex items-center justify-between p-3
         bg-slate-50 dark:bg-slate-700
         rounded-lg border border-slate-200 dark:border-slate-600;
}

.file-info {
  @apply flex items-center gap-2 flex-1 min-w-0;
}

.file-icon {
  @apply flex-shrink-0 text-slate-400;
}

.file-name {
  @apply text-sm hover:text-woot-500 dark:hover:text-woot-400
         text-slate-700 dark:text-slate-300 truncate max-w-[200px];
}

.file-source {
  @apply text-xs text-slate-500 dark:text-slate-400;
}

.file-meta {
  @apply text-xs text-slate-500 dark:text-slate-400 mt-0.5;
}

.delete-button {
  @apply p-1.5 text-slate-400 hover:text-n-ruby-9
         dark:text-slate-500 dark:hover:text-n-ruby-4
         rounded-md hover:bg-slate-100 dark:hover:bg-slate-600
         transition-colors flex-shrink-0;
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

/* Estilos do ícone de informação */
.info-icon-button {
  @apply h-10 w-10 flex items-center justify-center
         text-slate-400 hover:text-slate-600
         dark:text-slate-500 dark:hover:text-slate-400
         bg-slate-50 hover:bg-slate-100
         dark:bg-slate-700 dark:hover:bg-slate-600
         rounded-lg transition-colors cursor-help
         border border-slate-200 dark:border-slate-600;
}

/* Estilos do popover */
.formats-popover {
  @apply absolute top-full left-0 mt-2 w-80
         bg-white dark:bg-slate-800
         border border-slate-200 dark:border-slate-700
         rounded-lg shadow-lg z-50
         p-4;
}

.popover-header {
  @apply text-sm font-medium text-slate-700 dark:text-slate-300
         mb-3 pb-2 border-b border-slate-200 dark:border-slate-700;
}

.formats-list {
  @apply space-y-2;
}

.format-category {
  @apply text-xs text-slate-600 dark:text-slate-400;
}

.format-category strong {
  @apply text-slate-700 dark:text-slate-300;
}

.format-limit {
  @apply text-xs text-slate-500 dark:text-slate-500
         mt-3 pt-2 border-t border-slate-200 dark:border-slate-700;
}

/* Responsividade */
@media (max-width: 640px) {
  .images-grid {
    @apply grid-cols-4 gap-1;
  }

  .image-card {
    @apply rounded-sm;
  }

  .attachment-preview {
    @apply h-12;
  }

  .attachment-name {
    @apply max-w-[60px];
  }

  .file-name {
    @apply max-w-[150px];
  }

  .formats-popover {
    @apply w-72 right-0 left-auto;
  }

  .info-icon-button {
    @apply p-0.5;
  }
}

</style>
