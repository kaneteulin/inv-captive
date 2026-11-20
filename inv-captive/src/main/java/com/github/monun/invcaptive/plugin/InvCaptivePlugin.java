/*
 * InvCaptive for Paper 26.3
 *
 * Original work: InvCaptive 0.2.0 (InvCaptivePlugin.kt) by Noonmaru
 *   https://github.com/monun/inv-captive - GPL-3.0
 *
 * Modified 2026-11-20 by kaneteulin:
 *   - Rewritten from Kotlin to Java for Paper 26.3 (Kotlin / ProtocolLib dependencies removed)
 *   - Legacy materials excluded from the unlock block pool
 *   - Inventory is actually saved to inventory.yml when a player quits
 *   - Added /invcaptive list and /invcaptive status commands
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of
 * the GNU General Public License as published by the Free Software Foundation, version 3.
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License (LICENSE.md) for more details.
 */
package com.github.monun.invcaptive.plugin;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.kyori.adventure.text.serializer.legacy.LegacyComponentSerializer;
import org.bukkit.Bukkit;
import org.bukkit.ChatColor;
import org.bukkit.Material;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.configuration.InvalidConfigurationException;
import org.bukkit.configuration.file.YamlConfiguration;
import org.bukkit.entity.Firework;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.entity.ItemSpawnEvent;
import org.bukkit.event.entity.PlayerDeathEvent;
import org.bukkit.event.inventory.InventoryAction;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.player.PlayerDropItemEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.player.PlayerSwapHandItemsEvent;
import org.bukkit.event.world.WorldSaveEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;
import org.bukkit.plugin.java.JavaPlugin;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumMap;
import java.util.List;
import java.util.Locale;
import java.util.Random;
import java.util.concurrent.ThreadLocalRandom;
import java.util.logging.Level;

/**
 * @author Noonmaru (original), kaneteulin (Paper 26.3 port)
 */
public final class InvCaptivePlugin extends JavaPlugin implements Listener {

    private static final int SLOT_COUNT = 9 * 4 + 5;

    // 월드 폴더에 저장 -> 월드를 새로 만들기 전까지 유지됨 (/invcaptive 초기화로는 지워지지 않음)
    private static final String LIST_VIEWED_FILE = "invcaptive-list-viewed.txt";

    private EnumMap<Material, Integer> slotsByType;
    private Material[] blocksBySlot;

    @Override
    @SuppressWarnings("deprecation")
    public void onEnable() {
        long seed = loadSeed();

        getServer().getPluginManager().registerEvents(this, this);
        loadInventory();

        List<Material> list = new ArrayList<>();
        for (Material material : Material.values()) {
            if (!material.isLegacy() && material.isBlock() && !material.isAir()) {
                list.add(material);
            }
        }
        Collections.shuffle(list, new Random(seed));

        EnumMap<Material, Integer> map = new EnumMap<>(Material.class);
        Material[] bySlot = new Material[SLOT_COUNT];

        for (int i = 0; i < SLOT_COUNT; i++) {
            map.put(list.get(i), i);
            bySlot[i] = list.get(i);
        }

        this.slotsByType = map;
        this.blocksBySlot = bySlot;

        for (Player player : Bukkit.getOnlinePlayers()) {
            InvCaptive.patch(player);
        }
    }

    @Override
    public void onDisable() {
        save();
    }

    private long loadSeed() {
        File folder = getDataFolder();
        folder.mkdirs();
        File file = new File(folder, "config.yml");
        YamlConfiguration config = new YamlConfiguration();

        try {
            if (file.exists()) {
                config.load(file);
            }

            if (config.contains("seed")) {
                return config.getLong("seed");
            }

            long seed = ThreadLocalRandom.current().nextLong();
            config.set("seed", seed);
            config.save(file);

            return seed;
        } catch (IOException | InvalidConfigurationException e) {
            throw new IllegalStateException("Failed to load seed", e);
        }
    }

    private void loadInventory() {
        File file = new File(getDataFolder(), "inventory.yml");
        if (!file.exists()) {
            return;
        }
        InvCaptive.load(YamlConfiguration.loadConfiguration(file));
    }

    private void save() {
        YamlConfiguration yaml = InvCaptive.save();
        File folder = getDataFolder();
        folder.mkdirs();

        try {
            yaml.save(new File(folder, "inventory.yml"));
        } catch (IOException e) {
            getLogger().log(Level.SEVERE, "Failed to save inventory.yml", e);
        }
    }

    @EventHandler
    public void onPlayerJoin(PlayerJoinEvent event) {
        InvCaptive.patch(event.getPlayer());
    }

    @EventHandler
    public void onPlayerQuit(PlayerQuitEvent event) {
        save();
    }

    @EventHandler
    public void onWorldSave(WorldSaveEvent event) {
        save();
    }

    @EventHandler
    public void onInventoryClick(InventoryClickEvent event) {
        ItemStack current = event.getCurrentItem();
        if (current != null && current.getType() == Material.BARRIER) {
            event.setCancelled(true);
            return;
        }

        if (event.getAction() == InventoryAction.HOTBAR_SWAP) {
            ItemStack item = event.getWhoClicked().getInventory().getItem(event.getHotbarButton());
            if (item != null && item.getType() == Material.BARRIER) {
                event.setCancelled(true);
            }
        }
    }

    @EventHandler
    public void onDropItem(PlayerDropItemEvent event) {
        if (event.getItemDrop().getItemStack().getType() == Material.BARRIER) {
            event.setCancelled(true);
        }
    }

    @EventHandler(ignoreCancelled = true)
    @SuppressWarnings("deprecation")
    public void onBlockBreak(BlockBreakEvent event) {
        Integer slot = slotsByType.get(event.getBlock().getType());
        if (slot == null || !InvCaptive.release(slot)) {
            return;
        }

        for (Player player : Bukkit.getOnlinePlayers()) {
            player.getWorld().spawn(player.getLocation(), Firework.class);
        }

        String blockName = event.getBlock().translationKey();
        if (blockName.startsWith("block.minecraft.")) {
            blockName = blockName.substring("block.minecraft.".length());
        }

        String message = ChatColor.RED + event.getPlayer().getName() + ChatColor.RESET + "님이 "
                + ChatColor.GOLD + blockName + " " + ChatColor.RESET
                + "블록을 파괴하여 인벤토리 잠금이 한칸 해제되었습니다!";

        Bukkit.broadcast(LegacyComponentSerializer.legacySection().deserialize(message));
    }

    @EventHandler
    public void onInteract(PlayerInteractEvent event) {
        ItemStack item = event.getItem();
        if (item != null && item.getType() == Material.BARRIER) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onItemSpawn(ItemSpawnEvent event) {
        if (event.getEntity().getItemStack().getType() == Material.BARRIER) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onSwap(PlayerSwapHandItemsEvent event) {
        if (event.getOffHandItem().getType() == Material.BARRIER || event.getMainHandItem().getType() == Material.BARRIER) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onPlayerDeath(PlayerDeathEvent event) {
        event.setKeepInventory(true);

        List<ItemStack> drops = event.getDrops();
        drops.clear();

        PlayerInventory inventory = event.getEntity().getInventory();
        for (int i = 0; i < inventory.getSize(); i++) {
            ItemStack itemStack = inventory.getItem(i);
            if (itemStack != null && !itemStack.isEmpty() && itemStack.getType() != Material.BARRIER) {
                drops.add(itemStack);
                inventory.setItem(i, null);
            }
        }
    }

    // ---------------------------------------------------------------- commands

    private static final String PERMISSION_ADMIN = "invcaptive.command";
    private static final String PERMISSION_STATUS = "invcaptive.status";

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (args.length == 0) {
            // 원본 동작: 인벤토리 잠금 초기화
            if (checkPermission(sender, PERMISSION_ADMIN)) {
                InvCaptive.captive();
            }
            return true;
        }

        switch (args[0].toLowerCase(Locale.ROOT)) {
            case "list" -> {
                if (checkPermission(sender, PERMISSION_ADMIN)) {
                    showList(sender);
                }
            }
            case "status" -> {
                if (checkPermission(sender, PERMISSION_STATUS)) {
                    showStatus(sender);
                }
            }
            default -> sender.sendMessage(Component.text("사용법: /" + label + " [list|status]", NamedTextColor.RED));
        }
        return true;
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length != 1) {
            return List.of();
        }

        List<String> result = new ArrayList<>();
        if (sender.hasPermission(PERMISSION_ADMIN) && "list".startsWith(args[0].toLowerCase(Locale.ROOT))) {
            result.add("list");
        }
        if (sender.hasPermission(PERMISSION_STATUS) && "status".startsWith(args[0].toLowerCase(Locale.ROOT))) {
            result.add("status");
        }
        return result;
    }

    private static boolean checkPermission(CommandSender sender, String permission) {
        if (sender.hasPermission(permission)) {
            return true;
        }
        sender.sendMessage(Component.text("이 명령어를 사용할 권한이 없습니다.", NamedTextColor.RED));
        return false;
    }

    @SuppressWarnings("deprecation")
    private void showList(CommandSender sender) {
        markListViewed(sender);

        sender.sendMessage(Component.text("===== InvCaptive 해금 블록 목록 =====", NamedTextColor.GOLD));

        for (int slot = 0; slot < SLOT_COUNT; slot++) {
            Material block = blocksBySlot[slot];

            Component state;
            if (slot == 0) {
                state = Component.text("시작 칸", NamedTextColor.GRAY);
            } else if (InvCaptive.isLocked(slot)) {
                state = Component.text("잠김", NamedTextColor.RED);
            } else {
                state = Component.text("해금", NamedTextColor.GREEN);
            }

            sender.sendMessage(Component.text()
                    .append(Component.text(String.format("[%2d] ", slot), NamedTextColor.DARK_GRAY))
                    .append(Component.text(slotName(slot) + " ", NamedTextColor.YELLOW))
                    .append(Component.translatable(block.getBlockTranslationKey(), NamedTextColor.WHITE))
                    .append(Component.text(" (" + block.getKey().getKey() + ") ", NamedTextColor.GRAY))
                    .append(state)
                    .build());
        }
    }

    private static String slotName(int slot) {
        if (slot < 9) return "핫바 " + (slot + 1);
        if (slot < 36) return "인벤토리 " + ((slot - 9) / 9 + 1) + "-" + ((slot - 9) % 9 + 1);
        return switch (slot) {
            case 36 -> "신발";
            case 37 -> "바지";
            case 38 -> "상의";
            case 39 -> "투구";
            default -> "왼손";
        };
    }

    private void showStatus(CommandSender sender) {
        if (isListViewed()) {
            sender.sendMessage(Component.text("현재 상태: 관리자가 아이템 목록을 확인하였음.", NamedTextColor.RED));
        } else {
            sender.sendMessage(Component.text("현재 상태: 관리자가 아이템 목록을 확인하지 않았음.", NamedTextColor.GREEN));
        }
    }

    private static Path listViewedFile() {
        return Bukkit.getWorlds().get(0).getWorldPath().resolve(LIST_VIEWED_FILE);
    }

    private static boolean isListViewed() {
        return Files.exists(listViewedFile());
    }

    private void markListViewed(CommandSender sender) {
        if (isListViewed()) {
            return;
        }

        try {
            Files.writeString(listViewedFile(), "viewed-by=" + sender.getName() + "\nviewed-at=" + Instant.now() + "\n");
            getLogger().info(sender.getName() + " viewed the unlock block list (recorded until world reset)");
        } catch (IOException e) {
            getLogger().log(Level.SEVERE, "Failed to record list view", e);
        }
    }
}
