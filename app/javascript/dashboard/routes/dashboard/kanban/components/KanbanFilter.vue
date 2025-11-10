<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-300"
      leave-active-class="transition-opacity duration-200"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        class="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4"
        @click.self="closeModal"
      >
        <Transition
          enter-active-class="transition-all duration-300 ease-out"
          leave-active-class="transition-all duration-200 ease-in"
          enter-from-class="opacity-0 scale-95 translate-y-4"
          enter-to-class="opacity-100 scale-100 translate-y-0"
          leave-from-class="opacity-100 scale-100 translate-y-0"
          leave-to-class="opacity-0 scale-95 translate-y-4"
        >
          <div class="bg-white dark:bg-slate-900 rounded-2xl shadow-2xl w-full max-w-2xl max-h-[calc(90vh+20px)] overflow-hidden border border-slate-100 dark:border-slate-800">
        <!-- Header -->
            <div class="flex items-center justify-between p-6">
              <h3 class="text-xl font-semibold text-gray-900 dark:text-white">
                {{ t('KANBAN.FILTER.TITLE') }}
              </h3>
              <button
                @click="closeModal"
                class="p-2 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-full transition-colors duration-200 group"
                :aria-label="t('KANBAN.FILTER.CLOSE_MODAL')"
              >
                <svg
                  class="w-5 h-5 text-slate-500 group-hover:text-slate-700 dark:group-hover:text-slate-300 transition-colors"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>

        <!-- Content -->
            <div class="p-6 overflow-y-auto max-h-[calc(90vh-140px)]" :style="{ minHeight: showSavedFiltersDropdown ? '700px' : 'auto' }">
              <!-- Error message -->
              <div v-if="filterError" class="mb-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg flex items-start gap-2">
                <svg class="w-5 h-5 text-red-500 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <div class="flex-1">
                  <p class="text-sm font-medium text-red-800 dark:text-red-200">{{ t('KANBAN.FILTER.ERROR_TITLE') }}</p>
                  <p class="text-xs text-red-600 dark:text-red-300 mt-1">{{ filterError }}</p>
                </div>
                <button @click="filterError = null" class="text-red-500 hover:text-red-700 dark:hover:text-red-300">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              </div>

              <div class="space-y-6">
          <!-- Quick Filters -->
          <div v-show="!showSavedFiltersDropdown">
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-3">
              {{ t('KANBAN.FILTER.QUICK_FILTERS') }}
            </label>
            <div class="relative">
              <button
                @click="toggleQuickFiltersDropdown"
                class="quick-filters-button w-full px-4 py-3 text-white font-medium rounded-xl shadow-lg hover:shadow-xl transition-all duration-200 flex items-center justify-between group"
                :style="{
                  backgroundColor: buttonHover ? '#1D4ED8' : '#2563EB',
                  border: showQuickFiltersDropdown ? '2px solid #93C5FD' : '1px solid #3B82F6'
                }"
                :class="{ 'shadow-xl': showQuickFiltersDropdown }"
                @mouseenter="buttonHover = true"
                @mouseleave="buttonHover = false"
              >
                <div class="flex items-center gap-3">
                  <svg class="w-5 h-5 transition-transform duration-200 group-hover:rotate-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
                  </svg>
                  <span class="text-white">{{ selectedQuickFilter || t('KANBAN.FILTER.SELECT_QUICK_FILTER') }}</span>
                </div>
                <svg
                  class="w-5 h-5 transition-transform duration-200"
                  :class="{ 'rotate-180': showQuickFiltersDropdown }"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                </svg>
              </button>

              <!-- Dropdown -->
              <Transition
                enter-active-class="transition-all duration-200 ease-out"
                leave-active-class="transition-all duration-150 ease-in"
                enter-from-class="opacity-0 scale-95 -translate-y-2"
                enter-to-class="opacity-100 scale-100 translate-y-0"
                leave-from-class="opacity-100 scale-100 translate-y-0"
                leave-to-class="opacity-0 scale-95 -translate-y-2"
              >
                <div
                  v-if="showQuickFiltersDropdown"
                  class="quick-filters-dropdown absolute top-full left-0 right-0 mt-2 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl shadow-xl z-10 overflow-hidden"
                  @click.stop
                >
                  <div class="max-h-60 overflow-y-auto p-2 space-y-2">
                    <button
                      v-for="filter in quickFilters"
                      :key="filter.value"
                      @click="selectQuickFilter(filter)"
                      class="w-full group relative overflow-hidden rounded-xl border transition-all duration-200 transform hover:scale-[1.02] active:scale-[0.98]"
                      :class="[
                        selectedQuickFilterValue === filter.value
                          ? 'border-blue-200 dark:border-blue-800 bg-gradient-to-r from-blue-50 to-blue-100 dark:from-blue-900/30 dark:to-blue-800/30 shadow-md ring-1 ring-blue-300/50 dark:ring-blue-500/20'
                          : 'border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 hover:border-slate-300 dark:hover:border-slate-600 hover:bg-slate-50 dark:hover:bg-slate-700 hover:shadow-sm'
                      ]"
                    >
                      <!-- Background gradient effect -->
                      <div class="absolute inset-0 bg-gradient-to-r from-transparent via-white/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300"></div>

                      <div class="relative flex items-center gap-4 p-4">
                        <!-- Icon with animated background -->
                        <div class="flex-shrink-0 relative">
                          <div
                            class="w-8 h-8 rounded-md flex items-center justify-center transition-all duration-200 shadow-sm text-white"
                            :style="{ backgroundColor: filter.color }"
                            :class="[
                              'group-hover:shadow-md group-hover:scale-110',
                              selectedQuickFilterValue === filter.value && 'ring-2 ring-white/30 ring-offset-1 ring-offset-slate-100 dark:ring-offset-slate-800'
                            ]"
                          >
                            <component :is="filter.icon" class="w-4 h-4" />
                          </div>
                          <!-- Selection indicator ring -->
                          <div
                            v-if="selectedQuickFilterValue === filter.value"
                            class="absolute -inset-1 rounded-md border-2 border-dashed animate-pulse"
                            :style="{ borderColor: filter.color }"
                          ></div>
                        </div>

                        <!-- Content -->
                        <div class="flex-1 min-w-0 text-left">
                          <div class="flex items-center gap-2 mb-1">
                            <div
                              class="font-semibold text-sm transition-colors duration-200"
                              :class="[
                                selectedQuickFilterValue === filter.value
                                  ? 'text-blue-900 dark:text-blue-100'
                                  : 'text-slate-900 dark:text-slate-200 group-hover:text-slate-900 dark:group-hover:text-slate-100'
                              ]"
                            >
                              {{ filter.label }}
                            </div>
                            <span
                              v-if="filter.value === 'this_week'"
                              class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 border border-slate-200 dark:border-slate-600"
                            >
                              {{ t('KANBAN.FILTER.WEEK_INDICATOR') }}
                            </span>
                          </div>
                          <div
                            class="text-xs transition-colors duration-200"
                            :class="[
                              selectedQuickFilterValue === filter.value
                                ? 'text-blue-700 dark:text-blue-300'
                                : 'text-slate-500 dark:text-slate-400 group-hover:text-slate-600 dark:group-hover:text-slate-300'
                            ]"
                          >
                            {{ filter.description }}
                          </div>
                        </div>

                        <!-- Selection indicator -->
                        <div
                          class="flex-shrink-0 transition-all duration-200"
                          :class="[
                            selectedQuickFilterValue === filter.value
                              ? 'opacity-100 scale-100'
                              : 'opacity-0 scale-75'
                          ]"
                        >
                          <div class="w-6 h-6 rounded-full bg-blue-500 flex items-center justify-center shadow-md">
                            <svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                            </svg>
                          </div>
                        </div>
                      </div>

                      <!-- Subtle bottom border -->
                      <div
                        class="absolute bottom-0 left-4 right-4 h-px bg-gradient-to-r transition-opacity duration-200"
                        :class="[
                          selectedQuickFilterValue === filter.value
                            ? 'from-blue-300 to-blue-200 opacity-50'
                            : 'from-slate-200 to-slate-100 dark:from-slate-600 dark:to-slate-700 opacity-0 group-hover:opacity-50'
                        ]"
                      ></div>
                    </button>
                  </div>
                </div>
              </Transition>
            </div>
          </div>

          <!-- Saved Filters -->
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-3">
              {{ t('KANBAN.FILTER.SAVED_FILTERS') }}
            </label>
            <div class="space-y-4">
              <!-- Save current filter -->
              <div class="flex gap-3 items-stretch">
                <input
                  v-model="savedFilterName"
                  type="text"
                  :placeholder="t('KANBAN.FILTER.FILTER_NAME_PLACEHOLDER')"
                  class="flex-1 px-4 py-3 h-12 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-700 text-slate-900 dark:text-white placeholder-slate-500 dark:placeholder-slate-400 focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200"
                />
                <button
                  @click="saveCurrentFilter"
                  :disabled="!savedFilterName.trim() || !hasActiveFilters"
                  class="px-4 py-3 h-12 rounded-xl transition-all duration-200 flex items-center gap-2"
                  :class="[
                    savedFilterName.trim()
                      ? 'bg-green-500 hover:bg-green-600 text-white'
                      : 'bg-slate-100 dark:bg-slate-600 text-slate-700 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-500 disabled:opacity-50 disabled:cursor-not-allowed'
                  ]"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"></path>
                  </svg>
                  {{ t('KANBAN.FILTER.SAVE') }}
                </button>
              </div>

              <!-- Load saved filters -->
              <div class="relative">
                <button
                  @click="toggleSavedFiltersDropdown"
                  class="saved-filters-button w-full px-4 py-3 text-white font-medium rounded-xl shadow-lg hover:shadow-xl transition-all duration-200 flex items-center justify-between group"
                  :style="{
                    backgroundColor: savedFiltersButtonHover ? '#1D4ED8' : '#2563EB',
                    border: showSavedFiltersDropdown ? '2px solid #93C5FD' : '1px solid #3B82F6'
                  }"
                  :class="{ 'shadow-xl': showSavedFiltersDropdown }"
                  @mouseenter="savedFiltersButtonHover = true"
                  @mouseleave="savedFiltersButtonHover = false"
                >
                  <div class="flex items-center gap-3">
                    <svg class="w-5 h-5 transition-transform duration-200 group-hover:rotate-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"></path>
                    </svg>
                    <span class="text-white">{{ selectedSavedFilter || t('KANBAN.FILTER.LOAD_SAVED_FILTER') }}</span>
                  </div>
                  <svg
                    class="w-5 h-5 transition-transform duration-200"
                    :class="{ 'rotate-180': showSavedFiltersDropdown }"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                  </svg>
                </button>

                <!-- Saved filters dropdown -->
                <Transition
                  enter-active-class="transition-all duration-200 ease-out"
                  leave-active-class="transition-all duration-150 ease-in"
                  enter-from-class="opacity-0 scale-95 -translate-y-2"
                  enter-to-class="opacity-100 scale-100 translate-y-0"
                  leave-from-class="opacity-100 scale-100 translate-y-0"
                  leave-to-class="opacity-0 scale-95 -translate-y-2"
                >
                  <div
                    v-if="showSavedFiltersDropdown"
                    class="saved-filters-dropdown absolute top-full left-0 right-0 mt-2 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl shadow-xl z-10 overflow-hidden"
                    @click.stop
                  >
                    <div class="max-h-60 overflow-y-auto p-2 space-y-2">
                      <div v-if="savedFilters.length === 0" class="text-center text-slate-500 dark:text-slate-400 py-4 text-sm">
                        {{ t('KANBAN.FILTER.NO_SAVED_FILTERS') }}
                      </div>
                      <div
                        v-for="filter in savedFilters"
                        :key="filter.name"
                        class="group relative overflow-hidden rounded-xl border transition-all duration-200 transform hover:scale-[1.02] active:scale-[0.98]"
                        :class="[
                          'border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 hover:border-slate-300 dark:hover:border-slate-600 hover:bg-slate-50 dark:hover:bg-slate-700 hover:shadow-sm'
                        ]"
                      >
                        <!-- Background gradient effect -->
                        <div class="absolute inset-0 bg-gradient-to-r from-transparent via-slate-100/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300"></div>

                        <div class="relative flex items-center p-4">
                          <!-- Content -->
                          <div class="flex-1 min-w-0 text-left">
                            <div class="font-semibold text-sm text-slate-900 dark:text-slate-200">
                              {{ filter.name }}
                            </div>
                            <div class="text-xs text-slate-500 dark:text-slate-400">
                              {{ new Date(filter.createdAt).toLocaleDateString('pt-BR') }}
                            </div>
                          </div>

                          <!-- Actions -->
                          <div class="flex items-center gap-2">
                            <button
                              @click="loadSavedFilter(filter)"
                              class="px-3 py-1.5 text-xs bg-blue-500 hover:bg-blue-600 text-white rounded-md transition-colors duration-200"
                            >
                              {{ t('KANBAN.FILTER.LOAD') }}
                            </button>
                            <button
                              @click="deleteSavedFilter(filter.name)"
                              class="p-1.5 text-xs text-red-500 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded transition-colors duration-200"
                            >
                              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                              </svg>
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </Transition>
              </div>
            </div>
          </div>

          <!-- Priority -->
          <div v-show="!showSavedFiltersDropdown">
                  <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-3">
                    {{ t('KANBAN.FILTER.PRIORITY_LABEL') }}
                  </label>
            <div class="flex flex-wrap gap-2">
                    <button
                      v-for="priority in priorities"
                      :key="priority.value"
                      @click="togglePriority(priority.value)"
                      :class="[
                        'px-4 py-2 text-sm font-medium rounded-full transition-all duration-200 transform hover:scale-105 active:scale-95',
                        (selectedPriorities && selectedPriorities.includes && selectedPriorities.includes(priority.value))
                          ? priority.value === 'urgent'
                            ? 'shadow-lg'
                            : 'shadow-lg'
                          : 'bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-600'
                      ]"
                      :style="{
                        backgroundColor: (selectedPriorities && selectedPriorities.includes && selectedPriorities.includes(priority.value))
                          ? priority.value === 'urgent'
                            ? '#FFDCE1'
                            : priority.value === 'high'
                              ? '#DBEAFE'
                              : priority.value === 'medium'
                                ? '#FEF3C7'
                                : '#D1FAE5'
                          : '',
                        color: (selectedPriorities && selectedPriorities.includes && selectedPriorities.includes(priority.value))
                          ? priority.value === 'urgent'
                            ? '#DC3B5D'
                            : priority.value === 'high'
                              ? '#1E40AF'
                              : priority.value === 'medium'
                                ? '#92400E'
                              : '#065F46'
                          : '',
                        boxShadow: (selectedPriorities && selectedPriorities.includes && selectedPriorities.includes(priority.value))
                          ? priority.value === 'urgent'
                            ? '0 10px 15px -3px rgba(255, 220, 225, 0.3), 0 4px 6px -2px rgba(255, 220, 225, 0.2)'
                            : priority.value === 'high'
                              ? '0 10px 15px -3px rgba(219, 234, 254, 0.3), 0 4px 6px -2px rgba(219, 234, 254, 0.2)'
                              : priority.value === 'medium'
                                ? '0 10px 15px -3px rgba(254, 243, 199, 0.3), 0 4px 6px -2px rgba(254, 243, 199, 0.2)'
                                : '0 10px 15px -3px rgba(209, 250, 229, 0.3), 0 4px 6px -2px rgba(209, 250, 229, 0.2)'
                          : ''
                      }"
                    >
                      {{ priority.label }}
              </button>
            </div>
          </div>

          <!-- Value -->
          <div v-show="!showSavedFiltersDropdown">
                  <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-3">
                    {{ t('KANBAN.FILTER.VALUE_LABEL') }}
                  </label>
                  <div class="flex gap-3">
                    <div class="flex-1">
                      <input
                        v-model.number="filters.valueMin"
                        type="number"
                        :placeholder="t('KANBAN.FILTER.VALUE.MIN_PLACEHOLDER')"
                        class="w-full px-4 py-3 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-700 text-slate-900 dark:text-white placeholder-slate-500 dark:placeholder-slate-400 focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200"
                      />
                    </div>
                    <div class="flex-1">
                      <input
                        v-model.number="filters.valueMax"
                        type="number"
                        :placeholder="t('KANBAN.FILTER.VALUE.MAX_PLACEHOLDER')"
                        class="w-full px-4 py-3 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-700 text-slate-900 dark:text-white placeholder-slate-500 dark:placeholder-slate-400 focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200"
                      />
                    </div>
            </div>
          </div>

          <!-- Agent -->
          <div v-show="!showSavedFiltersDropdown">
                  <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-3">
                    {{ t('KANBAN.FILTER.AGENT.LABEL') }}
                  </label>
                  <div class="relative">
                    <input
                      v-model="agentSearchQuery"
                      type="text"
                      :placeholder="t('KANBAN.FILTER.AGENT.SEARCH_PLACEHOLDER')"
                      class="w-full px-4 py-3 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-700 text-slate-900 dark:text-white placeholder-slate-500 dark:placeholder-slate-400 focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200 pr-10"
                    />
                    <div class="absolute inset-y-0 right-0 flex items-center pr-3">
                      <svg class="w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
                      </svg>
                    </div>
                  </div>
                  <div class="mt-3 max-h-48 overflow-y-auto">
                    <div
                      v-for="agent in agents"
                      :key="agent.id"
                      @click="filters.agent = filters.agent === agent.id ? '' : agent.id"
                      class="group relative overflow-hidden rounded-xl border transition-all duration-200 transform active:scale-[0.99] cursor-pointer mb-2"
                      :class="[
                        filters.agent === agent.id
                          ? 'border-blue-200 dark:border-blue-800 bg-gradient-to-r from-blue-50 to-blue-100 dark:from-blue-900/30 dark:to-blue-800/30 shadow-sm ring-1 ring-blue-300/50 dark:ring-blue-500/20'
                          : 'border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800'
                      ]"
                    >
                      <div class="relative flex items-center gap-4 p-4">
                        <!-- Avatar -->
                        <div class="flex-shrink-0 relative">
                          <div
                            class="w-10 h-10 rounded-full flex items-center justify-center shadow-sm text-white font-semibold text-sm transition-all duration-200"
                            :style="{
                              background: 'linear-gradient(135deg, #3B82F6 0%, #2563EB 100%)'
                            }"
                            :class="[
                              filters.agent === agent.id && 'ring-2 ring-white/30 ring-offset-1 ring-offset-slate-100 dark:ring-offset-slate-800'
                            ]"
                          >
                            {{ agent.name ? agent.name.charAt(0).toUpperCase() : '?' }}
                          </div>
                          <!-- Selection indicator ring -->
                          <div
                            v-if="filters.agent === agent.id"
                            class="absolute -inset-1 rounded-full border-2 border-dashed animate-pulse"
                            :style="{ borderColor: '#3B82F6' }"
                          ></div>
                        </div>

                        <!-- Content -->
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center gap-2 mb-1">
                            <div
                              class="font-semibold text-sm transition-colors duration-200 truncate"
                              :class="[
                                filters.agent === agent.id
                                  ? 'text-blue-900 dark:text-blue-100'
                                  : 'text-slate-900 dark:text-slate-200'
                              ]"
                            >
                              {{ agent.name }}
                            </div>
                            <div
                              v-if="filters.agent === agent.id"
                              class="flex-shrink-0 w-2 h-2 rounded-full bg-blue-500 animate-pulse"
                            ></div>
                          </div>
                          <div
                            class="text-xs transition-colors duration-200 truncate"
                            :class="[
                              filters.agent === agent.id
                                ? 'text-blue-700 dark:text-blue-300'
                                : 'text-slate-500 dark:text-slate-400'
                            ]"
                          >
                            {{ agent.email }}
                          </div>
                        </div>

                        <!-- Selection indicator -->
                        <div
                          class="flex-shrink-0 transition-all duration-200"
                          :class="[
                            filters.agent === agent.id
                              ? 'opacity-100 scale-100'
                              : 'opacity-0 scale-75'
                          ]"
                        >
                          <div class="w-6 h-6 rounded-full bg-blue-500 flex items-center justify-center shadow-md">
                            <svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                            </svg>
                          </div>
                        </div>
                      </div>

                      <!-- Subtle bottom border -->
                      <div
                        class="absolute bottom-0 left-4 right-4 h-px bg-gradient-to-r transition-opacity duration-200"
                        :class="[
                          filters.agent === agent.id
                            ? 'from-blue-300 to-blue-200 opacity-50'
                            : 'from-slate-200 to-slate-100 dark:from-slate-600 dark:to-slate-700 opacity-0'
                        ]"
                      ></div>
                    </div>
                    <div v-if="agents.length === 0 && agentSearchQuery" class="text-center text-slate-500 dark:text-slate-400 py-6 text-sm">
                      <svg class="w-8 h-8 mx-auto mb-2 text-slate-300 dark:text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"></path>
                      </svg>
                      {{ t('KANBAN.FILTER.AGENT.NO_AGENT_FOUND') }}
                    </div>
                    <div v-if="agents.length === 0 && !agentSearchQuery" class="text-center text-slate-500 dark:text-slate-400 py-6 text-sm">
                      <svg class="w-8 h-8 mx-auto mb-2 text-slate-300 dark:text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"></path>
                      </svg>
                      {{ t('KANBAN.FILTER.AGENT.LOADING_AGENTS') }}
                    </div>
                  </div>
          </div>

          <!-- Date -->
          <div v-show="!showSavedFiltersDropdown">
                  <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-3">
                    {{ t('KANBAN.FILTER.CREATION_PERIOD') }}
                  </label>
                  <div class="flex gap-3">
                    <div class="flex-1">
                      <input
                        v-model="filters.dateStart"
                        type="date"
                        class="w-full px-4 py-3 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-700 text-slate-900 dark:text-white focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200"
                      />
                    </div>
                    <div class="flex-1">
                      <input
                        v-model="filters.dateEnd"
                        type="date"
                        class="w-full px-4 py-3 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-700 text-slate-900 dark:text-white focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200"
                      />
                    </div>
                  </div>
            </div>

          <!-- Scheduled Date -->
          <div v-show="!showSavedFiltersDropdown">
                  <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-3">
                    {{ t('KANBAN.FILTER.SCHEDULING_PERIOD') }}
                  </label>
                  <div class="flex gap-3">
                    <div class="flex-1">
                      <input
                        v-model="filters.scheduledDateStart"
                        type="date"
                        :placeholder="t('KANBAN.FILTER.START_DATE_PLACEHOLDER')"
                        class="w-full px-4 py-3 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-700 text-slate-900 dark:text-white focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200"
                      />
                    </div>
                    <div class="flex-1">
                      <input
                        v-model="filters.scheduledDateEnd"
                        type="date"
                        :placeholder="t('KANBAN.FILTER.END_DATE_PLACEHOLDER')"
                        class="w-full px-4 py-3 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-700 text-slate-900 dark:text-white focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200"
                      />
                    </div>
                  </div>
                  <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">
                    {{ t('KANBAN.FILTER.SCHEDULING_PERIOD_HELP') }}
                  </p>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div v-show="!showSavedFiltersDropdown" class="border-t border-slate-100 dark:border-slate-700">
          <div class="flex items-center justify-between px-6 py-4">
            <!-- Clear Button -->
            <button
              @click="clearFilters"
              :disabled="!hasActiveFilters"
              class="inline-flex items-center gap-2 px-4 py-2.5 text-sm font-medium rounded-lg transition-colors duration-200"
              :class="hasActiveFilters
                ? 'text-red-600 dark:text-red-400 hover:text-red-700 dark:hover:text-red-300 hover:bg-red-50 dark:hover:bg-red-900/20'
                : 'text-slate-400 dark:text-slate-500 cursor-not-allowed'"
            >
              <svg
                class="w-4 h-4 transition-transform duration-200"
                :class="hasActiveFilters ? 'group-hover:rotate-12' : ''"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
              </svg>
              {{ t('KANBAN.FILTER.CLEAR') }}
            </button>

            <!-- Action Buttons -->
            <div class="flex items-center gap-3">
              <button
                @click="closeModal"
                class="px-4 py-2.5 text-sm font-medium text-slate-600 dark:text-slate-400 hover:text-slate-800 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors duration-200"
              >
                {{ t('KANBAN.FILTER.CANCEL') }}
              </button>

              <button
                @click="applyFilters"
                :disabled="!hasActiveFilters || isFilteringItems"
                class="inline-flex items-center gap-2 px-6 py-2.5 text-sm font-semibold text-white rounded-lg transition-all duration-200 transform active:scale-95"
                :style="hasActiveFilters && !isFilteringItems ? {
                  backgroundColor: '#2563EB',
                  border: '1px solid #3B82F6'
                } : {}"
                :class="hasActiveFilters && !isFilteringItems
                  ? 'shadow-lg hover:shadow-xl hover:scale-105 hover:bg-blue-700'
                  : 'bg-slate-400 dark:bg-slate-500 cursor-not-allowed'"
                @mouseenter="hasActiveFilters && !isFilteringItems && ($el.style.backgroundColor = '#1D4ED8')"
                @mouseleave="hasActiveFilters && !isFilteringItems && ($el.style.backgroundColor = '#2563EB')"
              >
                <!-- Loading spinner -->
                <svg
                  v-if="isFilteringItems"
                  class="w-4 h-4 animate-spin"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <span>{{ isFilteringItems ? t('KANBAN.FILTER.FILTERING') : t('KANBAN.FILTER.APPLY_FILTERS') }}</span>
                <svg
                  v-if="hasActiveFilters && !isFilteringItems"
                  class="w-4 h-4 transition-transform duration-200 group-hover:translate-x-0.5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6"></path>
                </svg>
              </button>
            </div>
          </div>
        </div>
  </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { ref, computed, watch, watchEffect, nextTick, onMounted } from 'vue'
import { useStore } from 'vuex'
import { useI18n } from 'vue-i18n'
import KanbanAPI from '../../../../api/kanban'

const { t } = useI18n()

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  initialFilters: {
    type: Object,
    default: () => ({}),
  },
  currentFunnel: {
    type: Object,
    default: null,
  },
  columns: {
    type: Array,
    default: () => [],
  },
  filteredResults: {
    type: Object,
    default: () => ({ total: 0, stages: {} }),
  },
  size: {
    type: String,
    default: '',
  },
})

const store = useStore()

const emit = defineEmits(['apply', 'close', 'filterResults'])

// Reactive filter state
const filters = ref({
  priorities: [],
  valueMin: null,
  valueMax: null,
  agent: '',
  dateStart: '',
  dateEnd: '',
  scheduledDateStart: '',
  scheduledDateEnd: '',
})

// Priority options
const priorities = computed(() => [
  { value: 'urgent', label: t('KANBAN.PRIORITY_LABELS.URGENT') },
  { value: 'high', label: t('KANBAN.PRIORITY_LABELS.HIGH') },
  { value: 'medium', label: t('KANBAN.PRIORITY_LABELS.MEDIUM') },
  { value: 'low', label: t('KANBAN.PRIORITY_LABELS.LOW') },
])

// Search query for agents
const agentSearchQuery = ref('')

// Quick filters state
const showQuickFiltersDropdown = ref(false)
const selectedQuickFilterValue = ref('')
const selectedQuickFilter = ref('')
const hoverColor = ref(null)
const buttonHover = ref(false)

// Saved filters state
const showSavedFiltersDropdown = ref(false)
const savedFiltersButtonHover = ref(false)
const savedFilterName = ref('')
const selectedSavedFilter = ref('')

// Loading state for API call
const isFilteringItems = ref(false)
const filterError = ref(null)

// Quick filters options
const quickFilters = computed(() => [
  {
    value: 'last_7_days',
    label: t('KANBAN.FILTER.QUICK_FILTER_LAST_7_DAYS'),
    description: t('KANBAN.FILTER.QUICK_FILTER_LAST_7_DAYS_DESC'),
    icon: 'IconClock',
    color: '#3B82F6' // blue-500
  },
  {
    value: 'last_month',
    label: t('KANBAN.FILTER.QUICK_FILTER_LAST_MONTH'),
    description: t('KANBAN.FILTER.QUICK_FILTER_LAST_MONTH_DESC'),
    icon: 'IconCalendar',
    color: '#8B5CF6' // violet-500
  },
  {
    value: 'today',
    label: t('KANBAN.FILTER.QUICK_FILTER_TODAY'),
    description: t('KANBAN.FILTER.QUICK_FILTER_TODAY_DESC'),
    icon: 'IconSun',
    color: '#F59E0B' // amber-500
  },
  {
    value: 'this_year',
    label: t('KANBAN.FILTER.QUICK_FILTER_THIS_YEAR'),
    description: t('KANBAN.FILTER.QUICK_FILTER_THIS_YEAR_DESC'),
    icon: 'IconCalendarDays',
    color: '#10B981' // emerald-500
  },
  {
    value: 'this_week',
    label: t('KANBAN.FILTER.QUICK_FILTER_THIS_WEEK'),
    description: t('KANBAN.FILTER.QUICK_FILTER_THIS_WEEK_DESC'),
    icon: 'IconCalendarWeek',
    color: '#EF4444' // red-500
  }
])

// Icon components (inline SVG)
const IconClock = {
  template: `
    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
    </svg>
  `
}

const IconCalendar = {
  template: `
    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
    </svg>
  `
}

const IconSun = {
  template: `
    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"></path>
    </svg>
  `
}

const IconCalendarDays = {
  template: `
    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 9h.01M12 9h.01M15 9h.01M9 12h.01M12 12h.01M15 12h.01M9 15h.01M12 15h.01M15 15h.01"></path>
    </svg>
  `
}

const IconCalendarWeek = {
  template: `
    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 9h6m-6 4h6m-6 4h6"></path>
    </svg>
  `
}

const IconBookmark = {
  template: `
    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"></path>
    </svg>
  `
}

// Filtered agents computed
const agents = computed(() => {
  const agentsFromStore = store.getters['agents/getAgents'] || [];
  if (!agentSearchQuery.value) return agentsFromStore;

  const query = agentSearchQuery.value.toLowerCase();
  return agentsFromStore.filter(
    agent =>
      agent && agent.name && agent.email &&
      (agent.name.toLowerCase().includes(query) ||
       agent.email.toLowerCase().includes(query))
  );
})

// Saved filters computed
const savedFilters = computed(() => {
  const filters = JSON.parse(localStorage.getItem('kanban_saved_filters') || '[]')
  return filters.map(filter => ({
    ...filter,
    icon: 'IconBookmark',
    color: '#6B7280' // gray-500
  }))
})

// Computed properties
const selectedPriorities = computed({
  get: () => filters.value.priorities || [],
  set: (value) => filters.value.priorities = value || [],
})

const hasActiveFilters = computed(() => {
  return selectedQuickFilterValue.value !== '' ||
         (filters.value.priorities && filters.value.priorities.length > 0) ||
         filters.value.valueMin !== null ||
         filters.value.valueMax !== null ||
         filters.value.agent !== '' ||
         filters.value.dateStart !== '' ||
         filters.value.dateEnd !== '' ||
         filters.value.scheduledDateStart !== '' ||
         filters.value.scheduledDateEnd !== ''
})


// Methods
const closeModal = () => {
  emit('close')
  showQuickFiltersDropdown.value = false
}

const toggleQuickFiltersDropdown = () => {
  showQuickFiltersDropdown.value = !showQuickFiltersDropdown.value
}

const selectQuickFilter = (filter) => {
  if (selectedQuickFilterValue.value === filter.value) {
    // Deselect if already selected
    selectedQuickFilterValue.value = ''
    selectedQuickFilter.value = ''
    showQuickFiltersDropdown.value = false

    // Clear related filters
    clearQuickFilter()
  } else {
    selectedQuickFilterValue.value = filter.value
    selectedQuickFilter.value = filter.label
    showQuickFiltersDropdown.value = false

    // Apply quick filter
    applyQuickFilter(filter)
  }
}

const applyQuickFilter = (filter) => {
  const today = new Date()
  const todayStr = today.toISOString().split('T')[0]

  switch (filter.value) {
    case 'last_7_days': {
      const sevenDaysAgo = new Date()
      sevenDaysAgo.setDate(today.getDate() - 7)
      filters.value.priorities = []
      filters.value.valueMin = null
      filters.value.valueMax = null
      filters.value.agent = ''
      filters.value.dateStart = sevenDaysAgo.toISOString().split('T')[0]
      filters.value.dateEnd = todayStr
      break
    }

    case 'last_month': {
      const lastMonth = new Date()
      lastMonth.setMonth(today.getMonth() - 1)
      lastMonth.setDate(1)
      const lastMonthEnd = new Date(today.getFullYear(), today.getMonth(), 0)
      filters.value.priorities = []
      filters.value.valueMin = null
      filters.value.valueMax = null
      filters.value.agent = ''
      filters.value.dateStart = lastMonth.toISOString().split('T')[0]
      filters.value.dateEnd = lastMonthEnd.toISOString().split('T')[0]
      break
    }

    case 'today':
      filters.value.priorities = []
      filters.value.valueMin = null
      filters.value.valueMax = null
      filters.value.agent = ''
      filters.value.dateStart = todayStr
      filters.value.dateEnd = todayStr
      break

    case 'this_year': {
      const startOfYear = new Date(today.getFullYear(), 0, 1)
      filters.value.priorities = []
      filters.value.valueMin = null
      filters.value.valueMax = null
      filters.value.agent = ''
      filters.value.dateStart = startOfYear.toISOString().split('T')[0]
      filters.value.dateEnd = todayStr
      break
    }

    case 'this_week': {
      // Semana começa na segunda-feira
      const dayOfWeek = today.getDay() // 0 = domingo, 1 = segunda, etc.
      const monday = new Date(today)
      const sunday = new Date(today)

      // Se hoje é domingo (0), segunda-feira é 6 dias atrás
      // Se hoje é segunda (1), segunda-feira é hoje
      const daysFromMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1
      monday.setDate(today.getDate() - daysFromMonday)
      sunday.setDate(monday.getDate() + 6)

      filters.value.priorities = []
      filters.value.valueMin = null
      filters.value.valueMax = null
      filters.value.agent = ''
      filters.value.dateStart = monday.toISOString().split('T')[0]
      filters.value.dateEnd = sunday.toISOString().split('T')[0]
      break
    }
  }
}

const clearQuickFilter = () => {
  filters.value.priorities = []
  filters.value.valueMin = null
  filters.value.valueMax = null
  filters.value.agent = ''
  filters.value.dateStart = ''
  filters.value.dateEnd = ''
  filters.value.scheduledDateStart = ''
  filters.value.scheduledDateEnd = ''
  selectedQuickFilterValue.value = ''
  selectedQuickFilter.value = ''
}

// Saved filters methods
const saveCurrentFilter = () => {
  if (!savedFilterName.value.trim()) return

  const currentFilters = {
    name: savedFilterName.value.trim(),
    filters: { ...filters.value },
    createdAt: new Date().toISOString()
  }

  const existingFilters = JSON.parse(localStorage.getItem('kanban_saved_filters') || '[]')
  const updatedFilters = [...existingFilters, currentFilters]

  localStorage.setItem('kanban_saved_filters', JSON.stringify(updatedFilters))
  savedFilterName.value = ''

  // Force computed update
  savedFilters.value
}

const loadSavedFilter = (savedFilter) => {
  // Clear all current filters first
  filters.value = {
    priorities: [],
    valueMin: null,
    valueMax: null,
    agent: '',
    dateStart: '',
    dateEnd: '',
    scheduledDateStart: '',
    scheduledDateEnd: '',
  }

  // Update UI state
  selectedSavedFilter.value = savedFilter.name
  showSavedFiltersDropdown.value = false
  selectedQuickFilterValue.value = ''
  selectedQuickFilter.value = ''

  // Apply saved filter data with nextTick to ensure reactive updates
  nextTick(() => {
    filters.value = {
      priorities: [],
      valueMin: null,
      valueMax: null,
      agent: '',
      dateStart: '',
      dateEnd: '',
      scheduledDateStart: '',
      scheduledDateEnd: '',
      ...savedFilter.filters
    }

    // Clear agent search query to refresh agent list display
    agentSearchQuery.value = ''

    // Automatically apply the loaded filters
    applyFilters()
  })
}

const deleteSavedFilter = (filterName) => {
  const existingFilters = JSON.parse(localStorage.getItem('kanban_saved_filters') || '[]')
  const updatedFilters = existingFilters.filter(f => f.name !== filterName)
  localStorage.setItem('kanban_saved_filters', JSON.stringify(updatedFilters))

  // Force computed update
  savedFilters.value
}

const toggleSavedFiltersDropdown = () => {
  showSavedFiltersDropdown.value = !showSavedFiltersDropdown.value
}

const togglePriority = (priority) => {
  const currentPriorities = selectedPriorities.value || []
  const index = currentPriorities.indexOf(priority)
  if (index > -1) {
    currentPriorities.splice(index, 1)
  } else {
    currentPriorities.push(priority)
  }
  selectedPriorities.value = [...currentPriorities]
}

const applyFilters = async () => {
  // Clean up empty values
  const cleanFilters = {
    ...filters.value,
    valueMin: filters.value.valueMin || null,
    valueMax: filters.value.valueMax || null,
  }

  console.log('[KanbanFilter] applyFilters - Filtros limpos antes do emit:', cleanFilters)
  
  // Emitir filtros para compatibilidade com sistema existente
  emit('apply', cleanFilters)
  console.log('[KanbanFilter] applyFilters - Emit apply realizado')

  // Se não há filtros ativos, não faz a chamada da API
  if (!hasActiveFilters.value) {
    emit('filterResults', null)
    return
  }

  // Chamar API para buscar itens filtrados
  try {
    isFilteringItems.value = true
    filterError.value = null

    const response = await KanbanAPI.filterItems(cleanFilters)
    
    console.log('[KanbanFilter] applyFilters - Resposta da API:', response.data)
    
    // Emitir resultados para o componente pai
    emit('filterResults', response.data)
    
  } catch (error) {
    console.error('[KanbanFilter] Erro ao filtrar itens:', error)
    filterError.value = error.message || 'Erro ao filtrar itens'
    emit('filterResults', null)
  } finally {
    isFilteringItems.value = false
  }
}

const clearFilters = () => {
  filters.value = {
    priorities: [],
    valueMin: null,
    valueMax: null,
    agent: '',
    dateStart: '',
    dateEnd: '',
    scheduledDateStart: '',
    scheduledDateEnd: '',
  }
  agentSearchQuery.value = ''
  selectedQuickFilterValue.value = ''
  selectedQuickFilter.value = ''
  selectedSavedFilter.value = ''
  showQuickFiltersDropdown.value = false
  showSavedFiltersDropdown.value = false
  filterError.value = null
  emit('apply', {})
  emit('filterResults', null)
}

// Watch for initial filters prop changes
watch(() => props.initialFilters, (newFilters) => {
  console.log('[KanbanFilter] watch initialFilters - newFilters recebidos:', newFilters)
  if (newFilters) {
    // Merge filters properly, keeping default values
    filters.value = {
      priorities: [],
      valueMin: null,
      valueMax: null,
      agent: '',
      dateStart: '',
      dateEnd: '',
      scheduledDateStart: '',
      scheduledDateEnd: '',
      ...newFilters
    }
    console.log('[KanbanFilter] watch initialFilters - filters atualizados:', filters.value)
  } else {
    // Reset to defaults if no filters provided
    filters.value = {
      priorities: [],
      valueMin: null,
      valueMax: null,
      agent: '',
      dateStart: '',
      dateEnd: '',
      scheduledDateStart: '',
      scheduledDateEnd: '',
    }
  }
}, { immediate: true, deep: true })

// Watch for modal close to reset form
watch(() => props.show, (isShowing) => {
  if (!isShowing) {
    agentSearchQuery.value = ''
    showQuickFiltersDropdown.value = false
    showSavedFiltersDropdown.value = false
    savedFilterName.value = ''
    selectedSavedFilter.value = ''
  }
})

// Close dropdown when clicking outside
watchEffect(() => {
  if (showQuickFiltersDropdown.value) {
    const handleClickOutside = (event) => {
      const dropdown = document.querySelector('.quick-filters-dropdown')
      const button = document.querySelector('.quick-filters-button')
      if (dropdown && button && !dropdown.contains(event.target) && !button.contains(event.target)) {
        showQuickFiltersDropdown.value = false
      }
    }

    nextTick(() => {
      document.addEventListener('click', handleClickOutside)
    })

    return () => {
      document.removeEventListener('click', handleClickOutside)
    }
  }
})

// Close saved filters dropdown when clicking outside
watchEffect(() => {
  if (showSavedFiltersDropdown.value) {
    const handleClickOutside = (event) => {
      const dropdown = document.querySelector('.saved-filters-dropdown')
      const button = document.querySelector('.saved-filters-button')
      if (dropdown && button && !dropdown.contains(event.target) && !button.contains(event.target)) {
        showSavedFiltersDropdown.value = false
      }
    }

    nextTick(() => {
      document.addEventListener('click', handleClickOutside)
    })

    return () => {
      document.removeEventListener('click', handleClickOutside)
    }
  }
})

// Load agents on mount
onMounted(async () => {
  try {
    await store.dispatch('agents/get')
  } catch (error) {
    // Error handling
  }
})
</script>
