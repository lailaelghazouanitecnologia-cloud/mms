<script>
    let count = $state(0);
    let doubled = $derived(count * 2);

    function increment() {
        count++;
    }
</script>

<button on:click={increment}>
    Count: {count}
</button>

<p>Doubled: {doubled}</p>

{#if count > 10}
    <strong>Big number!</strong>
{:else}
    <span>Keep clicking</span>
{/if}

{#each items as item, i}
    <li>{i}: {item.name}</li>
{/each}

<img src="photo.jpg">

<style>
    button {
        background: blue;
        color: white;
    }
</style>
