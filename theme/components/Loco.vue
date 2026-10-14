<script setup lang="ts">
import { computed } from 'vue'
import { ribbonBits } from '../utils/ribbon.ts'
import locoUrl from '../assets/loco.png'

/**
 * The Turing-Express locomotive pulling a ribbon of bits.
 *
 * `text` seeds the bit sequence, `count` caps how many bits are generated
 * (only those fitting on one line are shown), `animate` reveals bits one by one.
 */
const props = withDefaults(defineProps<{
  text?: string
  count?: number
  animate?: boolean
}>(), {
  text: 'Turing-Express',
  count: 96,
  animate: true,
})

const bits = computed(() => ribbonBits(props.text, props.count))
</script>

<template>
  <div class="te-loco" :class="{ 'te-loco--animate': animate }">
    <div class="te-loco__ribbon">
      <span
        v-for="(bit, i) in bits"
        :key="i"
        class="te-loco__slot"
        :class="bit === 0 ? 'te-loco__slot--zero' : 'te-loco__slot--one'"
        :style="{ '--te-bit-index': i }"
      ><span class="te-loco__bit">{{ bit }}</span></span>
    </div>
    <img class="te-loco__motive" :src="locoUrl" alt="Turing-Express">
  </div>
</template>
