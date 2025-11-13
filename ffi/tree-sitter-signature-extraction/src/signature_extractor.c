#include "signature_extractor.h"
#include "utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


// Recursive function to traverse the AST and extract signatures
signature_node_t* traverse_and_extract(TSNode node, const char* source_code, const char* language, signature_node_t* parent) {
    if (ts_node_is_null(node)) {
        return NULL;
    }
    
    const char* node_type = ts_node_type(node);
    signature_node_t* sig_node = NULL;
    
    // Java specific processing
    if (strcmp(language, "java") == 0) {
        if (strcmp(node_type, "class_declaration") == 0) {
            sig_node = process_java_class(node, source_code);
        } else if (strcmp(node_type, "method_declaration") == 0) {
            sig_node = process_java_method(node, source_code);
        } else if (strcmp(node_type, "interface_declaration") == 0) {
            sig_node = process_java_interface(node, source_code);
        } else if (strcmp(node_type, "enum_declaration") == 0) {
            sig_node = process_java_enum(node, source_code);
        }
    }
    // Python specific processing
    else if (strcmp(language, "python") == 0) {
        if (strcmp(node_type, "class_definition") == 0) {
            sig_node = process_python_class(node, source_code);
        } else if (strcmp(node_type, "function_definition") == 0) {
            sig_node = process_python_function(node, source_code);
        }
    }
    
    // If we created a signature node, set its parent
    if (sig_node && parent) {
        add_child_signature_node(parent, sig_node);
    }
    
    // For the root node or when we don't have a signature node, continue with the same parent
    signature_node_t* current_parent = sig_node ? sig_node : parent;
    
    // Recursively process children
    uint32_t child_count = ts_node_child_count(node);
    for (uint32_t i = 0; i < child_count; i++) {
        TSNode child = ts_node_child(node, i);
        traverse_and_extract(child, source_code, language, current_parent);
    }
    
    return sig_node;
}

signature_node_t* extract_signatures(TSTree* tree, const char* source_code, const char* language) {
    if (!tree || !source_code || !language) {
        return NULL;
    }
    
    TSNode root_node = ts_tree_root_node(tree);
    
    // Create a dummy root node to hold all top-level signatures
    signature_node_t* root_container = create_signature_node(
        ENTITY_UNKNOWN, "root", "root", 0, 0, 0, 0
    );
    
    traverse_and_extract(root_node, source_code, language, root_container);
    
    // Return the children of the dummy root (the actual top-level signatures)
    signature_node_t* result = root_container->children;
    
    // Disconnect the children from the dummy root
    if (result) {
        signature_node_t* child = result;
        while (child) {
            child->parent = NULL;
            child = child->next_sibling;
        }
    }
    
    // Free the dummy root but not its children
    root_container->children = NULL;
    free_signature_node(root_container);
    
    return result;
}

signature_node_t* extract_signatures_from_file(const char *filepath, const char *language) {
    size_t source_size;
    char *source_code = read_file(filepath, &source_size);
    if (!source_code) {
        return NULL;
    }

    // Create a parser
    TSParser *parser = ts_parser_new();
    
    // Set the language
    TSLanguage *lang = NULL;
    if (strcmp(language, "java") == 0) {
        lang = tree_sitter_java();
    } else if (strcmp(language, "python") == 0) {
        lang = tree_sitter_python();
    } else {
        fprintf(stderr, "Unsupported language: %s\n", language);
        free(source_code);
        ts_parser_delete(parser);
        return NULL;
    }
    
    ts_parser_set_language(parser, lang);
    
    // Parse the source code
    TSTree *tree = ts_parser_parse_string(parser, NULL, source_code, source_size);
    
    // Extract signatures
    signature_node_t* signatures = extract_signatures(tree, source_code, language);
    
    // Clean up
    ts_tree_delete(tree);
    ts_parser_delete(parser);
    free(source_code);
    
    return signatures;
}

// Helper function to escape XML special characters
char* get_skeleton_xml(const char *filename, const char *language) {
    return get_skeleton_xml_range(filename, language, -1, -1);
}

char* get_skeleton_xml_range(const char *filename, const char *language, int start_line, int end_line) {
    // Extract signatures from the file
    signature_node_t* root = extract_signatures_from_file(filename, language);
    
    if (!root) {
        return NULL;
    }
    
    // Filter nodes based on line range if specified
    signature_node_t* filtered_root = NULL;
    if (start_line != -1 && end_line != -1) {
        // Create a new root container for filtered nodes
        filtered_root = create_signature_node(
            ENTITY_UNKNOWN, "root", "root", 0, 0, 0, 0
        );
        
        // Iterate through all top-level nodes
        signature_node_t* current = root;
        while (current) {
            // Check if this node overlaps with the range
            // entity.endLine >= target_startLine && entity.startLine <= target_endLine
            if ((current->end_line >= start_line && current->start_line <= end_line) ||
                (start_line == -1 && end_line == -1)) {
                // Add node to filtered results with range-based filtering of children
                signature_node_t* cloned_node = clone_signature_node_with_range(current, start_line, end_line);
                if (cloned_node) {
                    add_child_signature_node(filtered_root, cloned_node);
                }
            }
            current = current->next_sibling;
        }
    } else {
        filtered_root = root;
    }
    
    // Calculate approximate buffer size needed
    // Start with a reasonable base size for XML structure
    size_t buffer_size = 1024;
    signature_node_t* current = (start_line != -1 && end_line != -1) ? filtered_root->children : filtered_root;
    
    // Roughly estimate space needed for all signatures
    while (current) {
        if (current->signature) {
            buffer_size += strlen(current->signature) + 100; // Extra for XML tags
        }
        current = current->next_sibling;
        
        // Also account for children recursively
        signature_node_t* child = current ? current->children : NULL;
        while (child) {
            buffer_size += calculate_node_size_recursive(child);
            child = child->next_sibling;
        }
    }
    
    // Allocate buffer
    char* xml_buffer = (char*)malloc(buffer_size);
    if (!xml_buffer) {
        if (start_line != -1 && end_line != -1 && filtered_root) {
            free_signature_node(filtered_root);
        } else if (root && (start_line == -1 || end_line == -1)) {
            free_signature_node(root);
        }
        return NULL;
    }
    
    // Start building XML
    int offset = 0;
    if (start_line != -1 && end_line != -1) {
        offset += snprintf(xml_buffer + offset, buffer_size - offset, 
                           "<code-skeleton path=\"%s\" range=\"%d-%d\">\n", 
                           filename, start_line, end_line);
    } else {
        offset += snprintf(xml_buffer + offset, buffer_size - offset, 
                           "<code-skeleton path=\"%s\">\n", filename);
    }
    
    // Process all top-level nodes
    current = (start_line != -1 && end_line != -1) ? filtered_root->children : filtered_root;
    while (current) {
        if (current->signature) {
            offset = print_node_recursive(xml_buffer, buffer_size, current, offset, 1);
        }
        current = current->next_sibling;
    }
    
    offset += snprintf(xml_buffer + offset, buffer_size - offset, 
                       "</code-skeleton>");
    
    // Clean up
    if (start_line != -1 && end_line != -1 && filtered_root) {
        free_signature_node(filtered_root);
    } else if (root && (start_line == -1 || end_line == -1)) {
        free_signature_node(root);
    }
    
    return xml_buffer;
}

// Helper function to calculate the size needed for a node and all its descendants
size_t calculate_node_size_recursive(signature_node_t* node) {
    if (!node || !node->signature) return 0;
    
    size_t size = strlen(node->signature) + 100; // Base size for this node
    
    // Add size for all children recursively
    signature_node_t* child = node->children;
    while (child) {
        size += calculate_node_size_recursive(child);
        child = child->next_sibling;
    }
    
    return size;
}

// Helper function to recursively print a node and all its descendants
int print_node_recursive(char* buffer, size_t buffer_size, signature_node_t* node, int offset, int indent_level) {
    if (!node || !node->signature) return offset;
    
    // Print indentation
    for (int i = 0; i < indent_level; i++) {
        offset += snprintf(buffer + offset, buffer_size - offset, "    ");
    }
    
    // Print the code entity
    offset += snprintf(buffer + offset, buffer_size - offset,
                       "<code-entity start=%d end=%d>\n", 
                       node->start_line, node->end_line);
    
    // Print indentation for signature
    for (int i = 0; i < indent_level + 1; i++) {
        offset += snprintf(buffer + offset, buffer_size - offset, "    ");
    }
    
    // Escape special XML characters in signature
    char* escaped_signature = escape_xml(node->signature);
    if (escaped_signature) {
        offset += snprintf(buffer + offset, buffer_size - offset,
                           "<signature>%s</signature>\n", 
                           escaped_signature);
        free(escaped_signature);
    } else {
        offset += snprintf(buffer + offset, buffer_size - offset,
                           "<signature>%s</signature>\n", 
                           node->signature);
    }
    
    // Process children if they exist
    if (node->children) {
        // Print indentation for member
        for (int i = 0; i < indent_level + 1; i++) {
            offset += snprintf(buffer + offset, buffer_size - offset, "    ");
        }
        
        offset += snprintf(buffer + offset, buffer_size - offset,
                           "<member>\n");
        
        signature_node_t* child = node->children;
        while (child) {
            offset = print_node_recursive(buffer, buffer_size, child, offset, indent_level + 2);
            child = child->next_sibling;
        }
        
        // Print indentation for closing member tag
        for (int i = 0; i < indent_level + 1; i++) {
            offset += snprintf(buffer + offset, buffer_size - offset, "    ");
        }
        
        offset += snprintf(buffer + offset, buffer_size - offset,
                           "</member>\n");
    }
    
    // Print indentation for closing code-entity tag
    for (int i = 0; i < indent_level; i++) {
        offset += snprintf(buffer + offset, buffer_size - offset, "    ");
    }
    
    offset += snprintf(buffer + offset, buffer_size - offset,
                       "</code-entity>\n");
    
    return offset;
}

// Helper function to clone a signature node and its children with range filtering
signature_node_t* clone_signature_node_with_range(signature_node_t* node, int start_line, int end_line) {
    if (!node) return NULL;
    
    // Check if this node overlaps with the range
    // entity.endLine >= target_startLine && entity.startLine <= target_endLine
    if (!(node->end_line >= start_line && node->start_line <= end_line)) {
        return NULL; // Node doesn't overlap with range, don't include it
    }
    
    signature_node_t* clone = create_signature_node(
        node->type, node->name, node->signature,
        node->start_line, node->start_column,
        node->end_line, node->end_column
    );
    
    if (!clone) return NULL;
    
    // Clone children that also overlap with the range
    signature_node_t* child = node->children;
    while (child) {
        signature_node_t* cloned_child = clone_signature_node_with_range(child, start_line, end_line);
        if (cloned_child) {
            add_child_signature_node(clone, cloned_child);
        }
        child = child->next_sibling;
    }
    
    return clone;
}

// Helper function to clone a signature node and its children (without range filtering)
signature_node_t* clone_signature_node(signature_node_t* node) {
    if (!node) return NULL;
    
    signature_node_t* clone = create_signature_node(
        node->type, node->name, node->signature,
        node->start_line, node->start_column,
        node->end_line, node->end_column
    );
    
    if (!clone) return NULL;
    
    // Clone children
    signature_node_t* child = node->children;
    while (child) {
        signature_node_t* cloned_child = clone_signature_node(child);
        if (cloned_child) {
            add_child_signature_node(clone, cloned_child);
        }
        child = child->next_sibling;
    }
    
    return clone;
}
