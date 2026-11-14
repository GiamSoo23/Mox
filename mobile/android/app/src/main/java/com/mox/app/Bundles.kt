package com.mox.app

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.zip.CRC32
import java.util.zip.Inflater

/**
 * Several files sent as one zip (shared/PROTOCOL.md §9). The reader parses
 * the zip itself because java.util.zip doesn't say whether an entry is a
 * symbolic link, which the protocol must refuse.
 */
object Bundles {
    const val MAX_ENTRIES = 1000
    const val MAX_UNPACKED = CurrentFile.MAX_SIZE

    /** One file in a bundle: its path inside the bundle, and its bytes. */
    class Entry(val path: String, val data: ByteArray) {
        /** The last part of [path], the file's own name. */
        val name: String get() = path.substringAfterLast('/')
    }

    class Refused(reason: String) : Exception("Mox didn't unpack these files: $reason.")

    /** "Mox – 5 files.zip", the name the row carries. */
    fun fileName(count: Int) = "Mox – $count files.zip"

    /** Names for the files in a bundle, with " (1)" added where two are the same. */
    fun uniqueNames(names: List<String>): List<String> {
        val taken = mutableSetOf<String>()
        return names.map { name ->
            val stem = name.substringBeforeLast('.', name)
            val ext = if ('.' in name) "." + name.substringAfterLast('.') else ""
            var candidate = name
            var number = 1
            while (!taken.add(candidate)) candidate = "$stem (${number++})$ext"
            candidate
        }
    }

    /** Null if [files] (name → size) fit in 50 MB; otherwise why not, biggest first. */
    fun tooBig(files: List<Pair<String, Long>>): String? {
        val total = files.sumOf { it.second }
        if (total <= MAX_UNPACKED) return null
        val biggest = files.sortedByDescending { it.second }.take(3)
            .joinToString { "${it.first} (${humanBytes(it.second)})" }
        return "These files add up to ${humanBytes(
            total
        )}, and Mox sends up to 50 MB. The biggest: $biggest."
    }

    /** The files in a bundle, in order, or [Refused]. */
    fun read(zip: ByteArray): List<Entry> {
        val records = centralDirectory(zip)
        if (records.size > MAX_ENTRIES) throw Refused("it has too many files")
        val kept = mutableListOf<Record>()
        var total = 0L
        for (record in records) {
            check(record)
            if (isSkipped(record.name)) continue
            total += record.size
            if (total > MAX_UNPACKED) throw Refused("they add up to more than 50 MB")
            kept += record
        }
        if (kept.size < 2) throw Refused("a bundle has at least 2 files")
        return kept.map { Entry(it.name, contents(it, zip)) }
    }

    /** Packs [files] (path → bytes) into an uncompressed zip with UTF-8 names. */
    fun write(files: List<Pair<String, ByteArray>>): ByteArray {
        val out = ByteArrayOutputStream()
        val central = ByteArrayOutputStream()
        for ((path, data) in files) {
            val name = path.toByteArray(Charsets.UTF_8)
            val crc = CRC32().apply { update(data) }.value.toInt()
            val offset = out.size()
            out.write(header(LOCAL, name, crc, data.size, local = true))
            out.write(name)
            out.write(data)
            central.write(header(CENTRAL, name, crc, data.size, local = false))
            central.write(le32(offset))
            central.write(name)
        }
        val centralStart = out.size()
        out.write(central.toByteArray())
        out.write(le32(END) + le16(0) + le16(0) + le16(files.size) + le16(files.size))
        out.write(le32(central.size()) + le32(centralStart) + le16(0))
        return out.toByteArray()
    }

    // Rules

    private fun check(record: Record) {
        val name = record.name
        if ('\\' in name || name.startsWith("/") || (name.length > 1 && name[1] == ':') ||
            ".." in name.split("/")
        ) {
            throw Refused("“$name” points outside the folder")
        }
        if ((record.externalAttributes ushr 16) and 0xF000 ==
            0xA000
        ) {
            throw Refused("“$name” is a link")
        }
    }

    private fun isSkipped(name: String) = name.endsWith("/") || name.startsWith("__MACOSX/") ||
        name.substringAfterLast('/') == ".DS_Store"

    // Zip structure

    private const val LOCAL = 0x04034b50
    private const val CENTRAL = 0x02014b50
    private const val END = 0x06054b50

    private class Record(
        val name: String,
        val method: Int,
        val crc: Int,
        val compressedSize: Int,
        val size: Long,
        val externalAttributes: Int,
        val localHeader: Int
    )

    private fun centralDirectory(zip: ByteArray): List<Record> {
        val bytes = ByteBuffer.wrap(zip).order(ByteOrder.LITTLE_ENDIAN)
        val notZip = Refused("it isn't a zip")
        if (zip.size < 22) throw notZip
        val lowest = maxOf(0, zip.size - 22 - 65_535)
        var end = zip.size - 22
        while (end >= lowest && bytes.getInt(end) != END) end--
        if (end < lowest) throw notZip
        val count = bytes.u16(end + 10)
        var offset = bytes.u32(end + 16)
        val utf8 = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return List(count) {
            if (offset < 0 || offset + 46 > zip.size ||
                bytes.getInt(offset) != CENTRAL
            ) {
                throw notZip
            }
            val nameLength = bytes.u16(offset + 28)
            if (offset + 46 + nameLength > zip.size) throw notZip
            val name = try {
                utf8.decode(ByteBuffer.wrap(zip, offset + 46, nameLength)).toString()
            } catch (e: CharacterCodingException) {
                throw notZip
            }
            val record = Record(
                name = name,
                method = bytes.u16(offset + 10),
                crc = bytes.getInt(offset + 16),
                compressedSize = bytes.u32(offset + 20),
                size = bytes.getInt(offset + 24).toLong() and 0xFFFFFFFFL,
                externalAttributes = bytes.getInt(offset + 38),
                localHeader = bytes.u32(offset + 42)
            )
            offset += 46 + nameLength + bytes.u16(offset + 30) + bytes.u16(offset + 32)
            record
        }
    }

    private fun contents(record: Record, zip: ByteArray): ByteArray {
        val damaged = Refused("“${record.name}” is damaged")
        val bytes = ByteBuffer.wrap(zip).order(ByteOrder.LITTLE_ENDIAN)
        val header = record.localHeader
        if (header < 0 || header + 30 > zip.size || bytes.getInt(header) != LOCAL) throw damaged
        val start = header + 30 + bytes.u16(header + 26) + bytes.u16(header + 28)
        if (record.compressedSize < 0 || start + record.compressedSize > zip.size) throw damaged
        val stored = zip.copyOfRange(start, start + record.compressedSize)
        val data = when (record.method) {
            0 -> stored
            8 -> inflate(stored, record.size.toInt(), damaged)
            else -> throw Refused("“${record.name}” uses a compression Mox doesn't read")
        }
        val crc = CRC32().apply { update(data) }.value.toInt()
        if (data.size.toLong() != record.size || crc != record.crc) throw damaged
        return data
    }

    private fun inflate(input: ByteArray, size: Int, damaged: Refused): ByteArray {
        val inflater = Inflater(true)
        try {
            inflater.setInput(input)
            val output = ByteArray(size)
            var written = 0
            while (written < size && !inflater.finished()) {
                val n = inflater.inflate(output, written, size - written)
                if (n == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
                written += n
            }
            if (written != size) throw damaged
            return output
        } catch (e: java.util.zip.DataFormatException) {
            throw damaged
        } finally {
            inflater.end()
        }
    }

    private fun header(
        signature: Int,
        name: ByteArray,
        crc: Int,
        size: Int,
        local: Boolean
    ): ByteArray {
        var data = le32(signature)
        if (!local) data += le16(0x0314) // made by: Unix, zip 2.0
        data += le16(20) + le16(0x0800) + le16(0) // version, UTF-8 names, stored
        data += le16(0) + le16(0x5B6A) // fixed time and date
        data += le32(crc) + le32(size) + le32(size)
        data += le16(name.size) + le16(0)
        // Comment, disk, internal attributes, then: a regular file, 0644.
        if (!local) data += le16(0) + le16(0) + le16(0) + le32(0x81A4 shl 16)
        return data
    }

    private fun le16(value: Int) = byteArrayOf(value.toByte(), (value shr 8).toByte())
    private fun le32(value: Int) = le16(value and 0xFFFF) + le16(value ushr 16)
    private fun ByteBuffer.u16(index: Int) = getShort(index).toInt() and 0xFFFF
    private fun ByteBuffer.u32(index: Int) = getInt(index)
}
