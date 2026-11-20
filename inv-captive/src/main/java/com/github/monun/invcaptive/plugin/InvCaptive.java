package com.github.monun.invcaptive.plugin;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.minecraft.core.NonNullList;
import net.minecraft.world.entity.EntityEquipment;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import org.bukkit.Bukkit;
import org.bukkit.Material;
import org.bukkit.configuration.ConfigurationSection;
import org.bukkit.configuration.file.YamlConfiguration;
import org.bukkit.craftbukkit.entity.CraftPlayer;
import org.bukkit.craftbukkit.inventory.CraftItemStack;
import org.bukkit.entity.Player;
import org.bukkit.inventory.meta.ItemMeta;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/**
 * 모든 플레이어가 하나의 인벤토리를 공유하도록 서버 내부(NMS) 인벤토리를 교체한다.
 * <p>
 * 1.16 원본은 PlayerInventory 의 items / armor / extraSlots 리스트를 교체했다.
 * 1.21.5 부터 갑옷/왼손은 EntityEquipment 로 분리되었으므로
 * Inventory.items(36칸)와 EntityEquipment.items(장비 맵)를 공유 객체로 교체한다.
 */
public final class InvCaptive {
    private InvCaptive() {
    }

    private static final String ITEMS = "items";
    private static final String ARMOR = "armor";
    private static final String EXTRA_SLOTS = "extraSlots";

    // 1.16 PlayerInventory 와 같은 순서 (슬롯 36~39 = 신발, 바지, 상의, 투구 / 40 = 왼손)
    private static final EquipmentSlot[] ARMOR_SLOTS = {
            EquipmentSlot.FEET, EquipmentSlot.LEGS, EquipmentSlot.CHEST, EquipmentSlot.HEAD
    };
    private static final EquipmentSlot[] EXTRA_SLOTS_SLOTS = {EquipmentSlot.OFFHAND};

    private static final NonNullList<ItemStack> items = NonNullList.withSize(Inventory.INVENTORY_SIZE, ItemStack.EMPTY);
    private static final EnumMap<EquipmentSlot, ItemStack> equipment = new EnumMap<>(EquipmentSlot.class);

    private static final Field INVENTORY_ITEMS = field(Inventory.class, "items");
    private static final Field EQUIPMENT_ITEMS = field(EntityEquipment.class, "items");

    private static final ItemStack releaseSlotItem;

    static {
        org.bukkit.inventory.ItemStack item = new org.bukkit.inventory.ItemStack(Material.GOLDEN_APPLE);
        ItemMeta meta = item.getItemMeta();
        meta.displayName(Component.text("새로운 인벤토리", NamedTextColor.GOLD));
        item.setItemMeta(meta);
        releaseSlotItem = CraftItemStack.asNMSCopy(item);
    }

    private static Field field(Class<?> type, String name) {
        try {
            Field field = type.getDeclaredField(name);
            field.setAccessible(true);
            return field;
        } catch (NoSuchFieldException e) {
            throw new IllegalStateException("NMS field not found: " + type.getName() + "." + name, e);
        }
    }

    // ---------------------------------------------------------------- load / save

    public static void load(YamlConfiguration yaml) {
        List<ItemStack> loaded = loadItemStackList(yaml, ITEMS);
        for (int i = 0; i < Math.min(items.size(), loaded.size()); i++) {
            items.set(i, loaded.get(i));
        }
        loadEquipment(yaml, ARMOR, ARMOR_SLOTS);
        loadEquipment(yaml, EXTRA_SLOTS, EXTRA_SLOTS_SLOTS);
    }

    private static void loadEquipment(ConfigurationSection section, String name, EquipmentSlot[] slots) {
        List<ItemStack> loaded = loadItemStackList(section, name);
        for (int i = 0; i < Math.min(slots.length, loaded.size()); i++) {
            equipment.put(slots[i], loaded.get(i));
        }
    }

    @SuppressWarnings("unchecked")
    private static List<ItemStack> loadItemStackList(ConfigurationSection section, String name) {
        List<ItemStack> result = new ArrayList<>();
        for (Map<?, ?> map : section.getMapList(name)) {
            result.add(deserialize((Map<String, Object>) map));
        }
        return result;
    }

    private static ItemStack deserialize(Map<String, Object> map) {
        // 빈 칸은 {type: AIR} 로 저장됨 (아이템은 Paper 형식 {id: ..., count: ...} 또는 1.16 형식 {type: ...})
        if (map.isEmpty() || "AIR".equals(map.get("type"))) {
            return ItemStack.EMPTY;
        }
        return CraftItemStack.asNMSCopy(org.bukkit.inventory.ItemStack.deserialize(map));
    }

    public static YamlConfiguration save() {
        YamlConfiguration yaml = new YamlConfiguration();
        setItemStackList(yaml, ITEMS, items);
        setItemStackList(yaml, ARMOR, equipmentList(ARMOR_SLOTS));
        setItemStackList(yaml, EXTRA_SLOTS, equipmentList(EXTRA_SLOTS_SLOTS));
        return yaml;
    }

    private static List<ItemStack> equipmentList(EquipmentSlot[] slots) {
        List<ItemStack> list = new ArrayList<>(slots.length);
        for (EquipmentSlot slot : slots) {
            list.add(equipment.getOrDefault(slot, ItemStack.EMPTY));
        }
        return list;
    }

    private static void setItemStackList(ConfigurationSection section, String name, List<ItemStack> list) {
        List<Map<String, Object>> serialized = new ArrayList<>(list.size());
        for (ItemStack stack : list) {
            serialized.add(stack.isEmpty() ? Map.of("type", "AIR") : CraftItemStack.asBukkitCopy(stack).serialize());
        }
        section.set(name, serialized);
    }

    // ---------------------------------------------------------------- patch

    /**
     * 플레이어의 인벤토리/장비 저장소를 공유 객체로 교체한다.
     */
    public static void patch(Player player) {
        Inventory inventory = ((CraftPlayer) player).getHandle().getInventory();

        try {
            INVENTORY_ITEMS.set(inventory, items);
            // Inventory.equipment 와 LivingEntity.equipment 는 같은 객체
            EQUIPMENT_ITEMS.set(inventory.equipment, equipment);
        } catch (IllegalAccessException e) {
            throw new IllegalStateException("Failed to patch inventory of " + player.getName(), e);
        }
    }

    // ---------------------------------------------------------------- captive / release

    public static void captive() {
        ItemStack barrier = new ItemStack(Items.BARRIER);

        items.replaceAll(ignored -> barrier.copy());
        for (EquipmentSlot slot : ARMOR_SLOTS) {
            equipment.put(slot, barrier.copy());
        }
        for (EquipmentSlot slot : EXTRA_SLOTS_SLOTS) {
            equipment.put(slot, barrier.copy());
        }
        items.set(0, ItemStack.EMPTY);

        for (Player player : Bukkit.getOnlinePlayers()) {
            player.updateInventory();
        }
    }

    public static boolean release(int slot) {
        if (slot < 36) {
            if (isBarrier(items.get(slot))) {
                items.set(slot, releaseSlotItem.copy());
                return true;
            }
            return false;
        }

        EquipmentSlot equipmentSlot = slot < 40 ? ARMOR_SLOTS[slot - 36] : EXTRA_SLOTS_SLOTS[slot - 40];
        if (isBarrier(equipment.getOrDefault(equipmentSlot, ItemStack.EMPTY))) {
            equipment.put(equipmentSlot, releaseSlotItem.copy());
            return true;
        }
        return false;
    }

    /**
     * 해당 슬롯(0~40)이 아직 방벽으로 잠겨 있는지
     */
    public static boolean isLocked(int slot) {
        if (slot < 36) {
            return isBarrier(items.get(slot));
        }
        EquipmentSlot equipmentSlot = slot < 40 ? ARMOR_SLOTS[slot - 36] : EXTRA_SLOTS_SLOTS[slot - 40];
        return isBarrier(equipment.getOrDefault(equipmentSlot, ItemStack.EMPTY));
    }

    private static boolean isBarrier(ItemStack stack) {
        return stack.getItem() == Items.BARRIER;
    }
}
